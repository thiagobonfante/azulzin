# The monthly transactions hub (R3/R7/R8): index assembles the month's read model
# (MonthSummary), the pending tray (R8, unchanged scope), and the posted ledger. new/create
# power the ledger's inline add; edit/update the edit-in-place; assign/confirm the guarded
# inbox transitions. Chat and app are two front-ends over the same row, so the same guarded
# transitions apply. Every action answers a Turbo Stream with an HTML fallback.
class TransactionsController < ApplicationController
  layout "app"
  before_action :require_onboarding
  before_action :set_transaction, only: %i[edit update assign confirm destroy]

  helper_method :viewed_month, :summary

  def index
    return if redirect_out_of_range_month
    @month       = viewed_month
    @summary     = summary
    @pending     = Current.account.transactions.includes(:bank_account, :credit_card).pending_inbox.order(created_at: :desc)
    @occurrences = CommitmentOccurrence.for_month(Current.account, @month)          # zone E (R10)
    @ledger      = month_ledger
  end

  def new
    kind = %w[expense income transfer].include?(params[:kind]) ? params[:kind] : "expense"
    @transaction = Current.account.transactions.new(direction: kind, occurred_on: default_occurred_on)
    render partial: "transactions/new_entry", locals: { transaction: @transaction, kind: kind }
  end

  def create
    attrs = new_entry_params.to_h
    sanitize_account_fks(attrs)
    @transaction = Current.account.transactions.new(attrs)
    @transaction.assign_attributes(direction: new_kind, status: "posted", confirmed_at: Time.current, source: "manual")
    assign_instrument_from_token(params[:instrument])
    auto_assign_instrument      # server-side mirror of the form's auto-select (robust to JS)
    # A manual add with no instrument is a form slip, not a WhatsApp guess — 422 with the picker
    # error instead of silently posting into the "para revisar" tray (review is a WA concept).
    @transaction.errors.add(:base, :instrument_required) unless @transaction.instrument
    @saved = @transaction.errors.empty? && @transaction.save
    @ledger = month_ledger if @saved
    respond_to do |format|
      format.turbo_stream { render :create, status: (@saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to transactions_path(month: params[:month]),
                    notice: (@saved ? t("transactions.update.created") : nil),
                    alert: (@saved ? nil : @transaction.errors.full_messages.to_sentence)
      end
    end
  end

  def edit
    render partial: "transactions/edit_row", locals: { transaction: @transaction }
  end

  def update
    original_bill = @transaction.billing_month
    attrs = transaction_params.to_h
    bill  = attrs.delete("billing_month")
    sanitize_account_fks(attrs)
    attrs["category_id"] = nil if attrs["direction"] == "transfer"   # transfers are never categorized (§6.3.5)
    @transaction.assign_attributes(attrs)
    apply_bill_month_override(bill, original_bill)
    @saved = @transaction.save
    respond_to do |format|
      format.turbo_stream { render :update, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_to transactions_path(month: params[:month]), notice: (@saved ? t(".updated") : nil),
                    alert: (@saved ? nil : @transaction.errors.full_messages.to_sentence) }
    end
  end

  # Pick (or clear) the account/card an expense is charged to (tray).
  def assign
    if (record = resolve_instrument(params[:instrument]))
      @transaction.assign_instrument!(record)
    else
      @transaction.update!(bank_account: nil, credit_card: nil)
    end
    respond_to do |format|
      format.turbo_stream { render :row }
      format.html { redirect_to transactions_path(month: params[:month]), notice: t(".assigned") }
    end
  end

  # Confirm a pending / needs_* ask → posted (guarded, race-safe). Streams: leaves the tray,
  # travels into the viewed month's ledger.
  def confirm
    if installment_stub?(@transaction) && (@expanded = Installments::ExpandStub.call(@transaction))
      @confirmed = true
    else
      @confirmed = @transaction.guarded_update(Transaction::PENDING_INBOX_STATUSES, status: "posted", confirmed_at: Time.current)
    end
    respond_to do |format|
      format.turbo_stream { render :row }
      format.html { redirect_to transactions_path(month: params[:month]), notice: t(".confirmed") }
    end
  end

  # Soft delete (doc 05 §2.6): removed from all lists, restorable via console. reverse!/rejected
  # stays a WhatsApp-pipeline status (undo/supersede), not the in-app delete path.
  def destroy
    @transaction.soft_delete!(by: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to transactions_path(month: params[:month]), notice: t(".removed") }
    end
  end

  private
    def set_transaction
      @transaction = Current.account.transactions.kept.find(params[:id])
    end

    # The viewed month's posted ledger, ordered newest-first. Shared by index and create (which
    # re-renders the whole list so a first entry cleanly replaces the empty state).
    def month_ledger
      Current.account.transactions.posted_in(viewed_month)
             .includes(:bank_account, :credit_card, :category, :transfer_to_bank_account, :commitment)
             .order(occurred_on: :desc, id: :desc)
    end

    # A parked WhatsApp installment purchase (07 §4.4): confirming it fans out the real plan
    # rather than posting a single expense. Only while still pending (a superseded stub is done).
    def installment_stub?(txn)
      txn.extraction["installments_count"].present? && txn.installment_number.nil? &&
        Transaction::PENDING_INBOX_STATUSES.include?(txn.status)
    end

    # The viewed month, defaulting to today in São Paulo; regex-validated.
    def viewed_month
      @viewed_month ||= (parse_month(params[:month]) || sp_today.beginning_of_month)
    end

    def summary
      @summary ||= MonthSummary.new(Current.account, viewed_month)
    end

    def sp_today = Date.current.in_time_zone("America/Sao_Paulo").to_date

    # Adding on a past/future month defaults the date into that month (so the row bills there);
    # the current month defaults to today.
    def default_occurred_on
      (viewed_month..viewed_month.end_of_month).cover?(sp_today) ? sp_today : viewed_month
    end

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end

    # A valid but out-of-range month redirects to the nearest bound (crafted URLs can't render a
    # decade of empty months). Absent/garbage months resolve to today, no redirect.
    def redirect_out_of_range_month
      requested = parse_month(params[:month])
      return false if requested.nil?
      low  = (Current.account.transactions.kept.minimum(:billing_month) || sp_today).beginning_of_month
      high = sp_today.beginning_of_month >> 12
      clamped = requested.clamp(low, high)
      return false if clamped == requested
      redirect_to transactions_path(month: clamped.strftime("%Y-%m"))
      true
    end

    def new_kind = %w[expense income].include?(params[:kind]) ? params[:kind] : "expense"

    def new_entry_params = params.expect(transaction: %i[amount_reais merchant occurred_on category_id payment_method])

    def transaction_params
      params.expect(transaction: %i[amount_reais merchant occurred_on billing_month
                                    category_id direction transfer_to_bank_account_id])
    end

    # Reject FKs pointing at another account's (or a soft-deleted) record before they reach the row.
    def sanitize_account_fks(attrs)
      if attrs["category_id"].present? && !Current.account.categories.kept.exists?(attrs["category_id"])
        attrs["category_id"] = nil
      end
      if attrs["transfer_to_bank_account_id"].present? && !Current.account.bank_accounts.kept.exists?(attrs["transfer_to_bank_account_id"])
        attrs["transfer_to_bank_account_id"] = nil
      end
    end

    # A manual fatura move (R2) happens only when the submitted month differs from the row's
    # current billing_month — so editing occurred_on without touching the Fatura select never
    # accidentally sets the sticky flag. Bank rows carry no fatura; the param is ignored for them.
    def apply_bill_month_override(raw, original_bill)
      return unless raw.present? && @transaction.credit_card_id
      chosen = (Date.parse(raw).beginning_of_month rescue nil)
      return unless chosen && chosen != original_bill
      @transaction.billing_month = chosen
      @transaction.billing_month_manual = true
    end

    def assign_instrument_from_token(token)
      return unless token.present? && (record = resolve_instrument(token))
      case record
      when BankAccount then @transaction.bank_account = record
      when CreditCard  then @transaction.credit_card  = record
      end
    end

    # Manual add safety net: if no instrument came through (JS off / didn't fire), mirror the
    # form's auto-select on the server — a lone card for crédito, a lone account otherwise — so
    # a quick entry never silently lands in the "para revisar" tray as unassigned (R4/item 4).
    def auto_assign_instrument
      return if @transaction.bank_account_id || @transaction.credit_card_id
      if @transaction.payment_method == "credito"
        cards = Current.account.credit_cards.kept.to_a
        @transaction.credit_card = cards.first if cards.one?
      else
        accounts = Current.account.bank_accounts.kept.to_a
        @transaction.bank_account = accounts.first if accounts.one?
      end
    end

    def resolve_instrument(token)
      type, id = token.to_s.split("-", 2)
      case type
      when "bank_account" then Current.account.bank_accounts.kept.find_by(id: id)
      when "credit_card"  then Current.account.credit_cards.kept.find_by(id: id)
      end
    end
end
