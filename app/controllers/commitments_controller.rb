# Recurring commitments (R10) and card installment parents (R11). index/show are two pages;
# create branches: a card installment fans out via Installments::Create, everything else is a
# plain schedule definition whose occurrences are computed. See 05-commitments.md.
class CommitmentsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: %i[index show]

  def index
    @commitments = Current.user.commitments.active.includes(:bank_account, :credit_card, :category).order(:kind, :created_at)
    @archived    = Current.user.commitments.where.not(archived_at: nil).includes(:bank_account, :credit_card)
    @commitment  = Commitment.new
  end

  def show
    @commitment  = Current.user.commitments.find(params[:id])
    @occurrences = vencimentos(@commitment)
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
    @commitment = Current.user.commitments.find(params[:id])
    if @commitment.update(commitment_update_params)
      redirect_to commitment_path(@commitment), notice: t("commitments.show.updated")
    else
      @occurrences = vencimentos(@commitment)
      render :show, status: :unprocessable_entity
    end
  end

  # Hard delete only when no posted payments exist (don't orphan visible history); otherwise
  # archive — history kept, occurrences stop.
  def destroy
    @commitment = Current.user.commitments.find(params[:id])
    if @commitment.payments.posted.exists?
      @commitment.update!(archived_at: Time.current)
    else
      @commitment.destroy
    end
    redirect_to commitments_path, notice: t(".removed")
  end

  private
    def commitment_params
      params.expect(commitment: %i[name kind amount_reais installments_count installments_paid
                                   schedule_day ends_on category_id])
    end

    def commitment_update_params
      params.expect(commitment: %i[name amount_reais schedule_day ends_on category_id])
            .to_h.tap { |h| h["category_id"] = sanitized_category(h["category_id"]) }
    end

    def build_commitment(instrument)
      p = commitment_params
      c = Current.user.commitments.new(name: p[:name], kind: p[:kind], amount_reais: p[:amount_reais],
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
        c.ends_on = p[:ends_on].presence
      end
      c
    end

    def create_card_installment(card)
      p = commitment_params
      count  = p[:installments_count].to_i
      parcel = Money.to_cents(p[:amount_reais]).to_i
      if count < 1 || parcel < 1
        return Current.user.commitments.new(kind: "installment", credit_card: card).tap { |c| c.valid? }
      end
      Installments::Create.call(user: Current.user, card: card, total_cents: parcel * count, count: count,
                                occurred_on: sp_today, merchant: p[:name], category_id: sanitized_category(p[:category_id]))
    rescue ActiveRecord::RecordInvalid => e
      e.record
    end

    # Retroactive link (05 §5.7 pass 2): a just-created card subscription/fixed adopts a matching
    # posted charge already on that card this bill — the projection drops out, the bill is constant.
    def link_existing_card_charge(commitment)
      return unless commitment.card? && %w[subscription fixed].include?(commitment.kind)
      month = commitment.credit_card.billing_month_for(sp_today)
      candidates = commitment.credit_card.transactions.posted
                             .where(billing_month: month, commitment_id: nil, direction: "expense").to_a
      best = candidates.select { |t| amount_close?(t.amount_cents, commitment.amount_cents) }
                       .max_by { |t| name_similarity(t.merchant, commitment.name) }
      return unless best && name_similarity(best.merchant, commitment.name) >= 0.6
      best.update!(commitment_id: commitment.id)
    rescue ActiveRecord::RecordNotUnique
      # another charge already occupies this commitment-month slot → leave unlinked
    end

    def name_similarity(a, b) = Whatsapp.similarity(Whatsapp.normalize(a.to_s), Whatsapp.normalize(b.to_s))

    def amount_close?(a, b)
      tol = [ (b.to_i * 0.2).round, 500 ].max
      (a.to_i - b.to_i).abs <= tol
    end

    # Vencimentos list, newest first, over [starts_on .. min(last occurrence, current + 12mo)].
    def vencimentos(commitment)
      first = commitment.starts_on.beginning_of_month
      last  = [ commitment.last_month&.beginning_of_month || (Date.current.beginning_of_month >> 12),
                Date.current.beginning_of_month >> 12 ].min
      payments = commitment.payments.posted.index_by(&:billing_month)
      months, m = [], last
      while m >= first
        months << m
        m = m << 1
      end
      months.map { |mo| CommitmentOccurrence.new(commitment, mo, payment: payments[mo]) }
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
      when "bank_account" then Current.user.bank_accounts.find_by(id: id)
      when "credit_card"  then Current.user.credit_cards.find_by(id: id)
      end
    end

    def sanitized_category(id) = (id if id.present? && Current.user.categories.exists?(id))

    def sp_today = Date.current.in_time_zone("America/Sao_Paulo").to_date
end
