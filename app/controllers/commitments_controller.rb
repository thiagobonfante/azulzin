# Recurring commitments (R10) and card installment parents (R11). index/show are two pages;
# create branches: a card installment fans out via Installments::Create, everything else is a
# plain schedule definition whose occurrences are computed. See 05-commitments.md.
class CommitmentsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: %i[index show]
  before_action :require_instrument, only: :create

  def index
    @commitments = Current.account.commitments.kept.active.includes(:bank_account, :credit_card, :category).order(:kind, :created_at)
    @archived    = Current.account.commitments.kept.where.not(archived_at: nil).includes(:bank_account, :credit_card, :category)
    @commitment  = Commitment.new
  end

  def show
    @commitment = Current.account.commitments.kept.find(params[:id])
  end

  def create
    instrument = resolve_instrument(params[:instrument])
    if commitment_params[:kind] == "installment" && instrument.is_a?(CreditCard)
      @commitment = create_card_installment(instrument)
    else
      @commitment = build_commitment(instrument)
      if @commitment.save
        link_existing_card_charge(@commitment)
      end
    end
    saved = @commitment&.persisted?
    respond_to do |format|
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to commitments_path, notice: (saved ? t(".created") : nil),
                    alert: (saved ? nil : @commitment&.errors&.full_messages&.to_sentence)
      end
    end
  end

  def update
    @commitment = Current.account.commitments.kept.find(params[:id])
    @commitment.assign_attributes(commitment_update_params)
    saved = ActiveRecord::Base.transaction do
      Commitments::AdjustCount.call(@commitment, params.dig(:commitment, :installments_count)) &&
        @commitment.save || raise(ActiveRecord::Rollback)
    end
    if saved
      redirect_to commitment_path(@commitment), notice: t("commitments.show.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  # Early payoff (installments on debit): one posted transaction for the negotiated amount —
  # paying everything upfront usually means a discount, so the value is the user's — then the
  # plan is archived (occurrences stop, history kept).
  def settle
    @commitment = Current.account.commitments.kept.find(params[:id])
    amount = Money.to_cents(params[:amount_reais])
    if @commitment.installment? && !@commitment.card? && amount.to_i.positive? && @commitment.next_charge_month
      Commitments::Settle.call(@commitment, amount)
      redirect_to commitments_path, notice: t(".settled")
    else
      redirect_to commitment_path(@commitment), alert: t(".invalid")
    end
  end

  # Pay several selected parcels at once: the typed total is what the user actually handed
  # over (early batches usually carry a discount) — PayBatch splits it across the months.
  def pay_batch
    @commitment = Current.account.commitments.kept.find(params[:id])
    months = Array(params[:months]).filter_map { |m| parse_month(m) }
    amount = Money.to_cents(params[:amount_reais])
    if @commitment.card? || months.empty? || !amount.to_i.positive?
      return redirect_to commitment_path(@commitment), alert: t(".invalid")
    end
    Commitments::PayBatch.call(@commitment, months, amount)
    redirect_to commitment_path(@commitment), notice: t(".paid")
  end

  # Unconditional soft delete (doc 05 §2.6): the old archive-if-paid branch existed only because
  # hard destroy nullified payments' history; soft delete preserves it. archived_at stays a
  # business state set by Settle / future archive affordances.
  def destroy
    @commitment = Current.account.commitments.kept.find(params[:id])
    @commitment.soft_delete!(by: Current.user)
    redirect_to commitments_path, notice: t(".removed")
  end

  private
    # No instrument in the account yet (onboarding skipped): the index sidebar already swaps
    # the form for a "create an account or card first" prompt; this stops a direct POST.
    def require_instrument
      redirect_to commitments_path, alert: t("shared.needs_instrument.title") unless account_has_instruments?
    end

    def commitment_params
      params.expect(commitment: %i[name kind amount_reais installments_count installments_paid
                                   schedule_day ends_on category_id transfer_to_bank_account_id])
    end

    def commitment_update_params
      params.expect(commitment: %i[name amount_reais schedule_day ends_on category_id])
            .to_h.tap { |h| h["category_id"] = sanitized_category(h["category_id"]) }
    end

    def build_commitment(instrument)
      p = commitment_params
      c = Current.account.commitments.new(name: p[:name], kind: p[:kind], amount_reais: p[:amount_reais],
                                       schedule_day: p[:schedule_day].presence,
                                       category_id: sanitized_category(p[:category_id]))
      assign_commitment_instrument(c, instrument)
      case p[:kind]
      when "installment"
        count = p[:installments_count].to_i
        c.installments_count = count
        c.total_cents = c.amount_cents.to_i * count
        c.starts_on = Date.current.beginning_of_month << p[:installments_paid].to_i # mid-plan anchor
      else # fixed / subscription
        c.starts_on = Date.current.beginning_of_month
        # Created after the charge day already passed → the first occurrence is next month
        # (no retroactive "overdue" born on day one). A matching posted card charge rewinds
        # this in link_existing_card_charge.
        c.starts_on = c.starts_on >> 1 if c.due_on(c.starts_on) < Date.current
        c.ends_on = p[:ends_on].presence
      end
      c.transfer_to_bank_account_id = sanitized_savings_account_id(p[:transfer_to_bank_account_id]) if p[:kind] == "savings"
      c
    end

    def create_card_installment(card)
      p = commitment_params
      count  = p[:installments_count].to_i
      parcel = Money.to_cents(p[:amount_reais]).to_i
      if count < 1 || parcel < 1
        return Current.account.commitments.new(kind: "installment", credit_card: card).tap { |c| c.valid? }
      end
      Installments::Create.call(account: Current.account, created_by: Current.user, card: card,
                                total_cents: parcel * count, count: count,
                                occurred_on: sp_today, merchant: p[:name], category_id: sanitized_category(p[:category_id]))
    rescue ActiveRecord::RecordInvalid => e
      e.record
    end

    # Retroactive link (05 §5.7 pass 2): a just-created card subscription/fixed adopts a matching
    # posted charge already on that card this bill — the projection drops out, the bill is constant.
    def link_existing_card_charge(commitment)
      return unless commitment.card? && %w[subscription fixed].include?(commitment.kind)
      month = commitment.credit_card.billing_month_for(sp_today)
      candidates = commitment.credit_card.transactions.posted.kept
                             .where(billing_month: month, commitment_id: nil, direction: "expense").to_a
      best = candidates.select { |t| amount_close?(t.amount_cents, commitment.amount_cents) }
                       .max_by { |t| name_similarity(t.merchant, commitment.name) }
      return unless best && name_similarity(best.merchant, commitment.name) >= 0.6
      best.update!(commitment_id: commitment.id)
      # The charge proves this bill's occurrence happened — keep it (paid) even when
      # build_commitment pushed starts_on past the already-elapsed charge day.
      commitment.update!(starts_on: month) if month < commitment.starts_on
    rescue ActiveRecord::RecordNotUnique
      # another charge already occupies this commitment-month slot → leave unlinked
    end

    def name_similarity(a, b) = Whatsapp.similarity(Whatsapp.normalize(a.to_s), Whatsapp.normalize(b.to_s))

    def amount_close?(a, b)
      tol = [ (b.to_i * 0.2).round, 500 ].max
      (a.to_i - b.to_i).abs <= tol
    end

    def assign_commitment_instrument(commitment, instrument)
      case instrument
      when BankAccount then commitment.bank_account = instrument
      when CreditCard  then commitment.credit_card = instrument
      end
    end

    def resolve_instrument(token)
      type, id = token.to_s.split("-", 2)
      case type
      when "bank_account" then Current.account.bank_accounts.kept.find_by(id: id)
      when "credit_card"  then Current.account.credit_cards.kept.find_by(id: id)
      end
    end

    def sanitized_category(id) = (id if id.present? && Current.account.categories.kept.exists?(id))

    # Standalone savings destination: only a kept savings-kind account of THIS account passes
    # (model validation is the backstop; presence 422s when the whitelist drops a junk id).
    def sanitized_savings_account_id(id) = (id if id.present? && Current.account.bank_accounts.kept.savings.exists?(id))

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end

    def sp_today = Date.current.in_time_zone("America/Sao_Paulo").to_date
end
