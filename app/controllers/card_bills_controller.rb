# The closed-fatura page + Pagar flow (.plans/credit-cards 01 §4). Only CLOSED bills have
# rows (and therefore pages) — open months keep living in the hub's bills tile.
class CardBillsController < ApplicationController
  layout "app"
  before_action :require_onboarding
  before_action :set_bill

  def show
    @lines = @bill.credit_card.family_transactions.posted.kept
                  .where(billing_month: @bill.billing_month)
                  .includes(:commitment, credit_card: :institution).order(:occurred_on, :id)
    @payments = @bill.payments.posted.kept.includes(:bank_account).order(:occurred_on, :id)
  end

  def pay
    amount = Money.to_cents(params[:amount_reais]).to_i
    return redirect_to card_bill_path(@bill), alert: t(".invalid_amount") unless amount.positive?

    CardBills::Pay.call(@bill,
      amount_cents:         amount,
      paid_on:              paid_on,
      bank_account:         source_account,
      created_by:           Current.user)
    dismiss_notification
    redirect_to card_bill_path(@bill), notice: t(".paid")
  end

  def unpay
    payment = @bill.payments.posted.kept.find(params[:payment_id])
    payment.reverse!
    redirect_to card_bill_path(@bill), notice: t(".undone")
  end

  # The live partial-payment warning (.plans/credit-cards 02 §4): the Pagar modal fetches
  # this as the amount is typed — the projection math stays server-side.
  def projection
    typed = Money.to_cents(params[:amount_reais]).to_i
    render partial: "card_bills/rotativo_warning",
           locals: { bill: @bill, paid_cents: @bill.paid_cents + [ typed, 0 ].max }, layout: false
  end

  # Informing (or correcting) the bank's number (.plans/credit-cards 03 §1). A number that
  # already matches just confirms on the bill page; a divergence opens the focused
  # conferir page (founder round 2026-07-22: resolution needs full attention, not a card
  # mutating ad-hoc under the bill).
  def update
    stated = Money.to_cents(params[:stated_total_reais]).to_i
    return redirect_to card_bill_path(@bill), alert: t("card_bills.pay.invalid_amount") unless stated.positive?
    # A fresh conferência — whatever an older one did is settled history now.
    @bill.update!(stated_total_cents: stated, review_log: [])
    if @bill.our_total_cents == stated
      redirect_to card_bill_path(@bill), notice: t(".stated_saved")
    else
      redirect_to review_card_bill_path(@bill)
    end
  end

  # The divergence-resolution page: move closing-edge rows forward / add a missed
  # purchase / register an adjustment / cancel. Only exists while UNRESOLVED — a matched
  # or value-less bill goes home.
  def review
    return redirect_to card_bill_path(@bill) unless @bill.divergence_pending?
    # Only plausible left-behind candidates: rows within 2 days of closing (founder call
    # 2026-07-22 — anything older isn't "o banco jogou pra frente").
    @edge_lines = @bill.credit_card.family_transactions.posted.kept
                       .where(billing_month: @bill.billing_month,
                              occurred_on: (@bill.closed_on - 2)..@bill.closed_on)
                       .includes(:commitment, credit_card: :institution).order(:occurred_on, :id)
  end

  # Purchases the user found missing during the review (one or more rows): normal card
  # expenses, dates clamped to THIS bill's window (previous closing + 1 .. closing).
  # NOT review-logged — real spending survives a cancelled conferência.
  def add_line
    return redirect_to card_bill_path(@bill) unless @bill.divergence_pending?
    window_start = @bill.credit_card.closing_date(@bill.billing_month << 1) + 1
    created = Array(params[:merchants]).zip(Array(params[:amounts_reais]), Array(params[:occurred_ons])).count do |merchant, amount_reais, occurred_str|
      amount = Money.to_cents(amount_reais).to_i
      next false unless amount.positive?
      occurred = begin
        Date.iso8601(occurred_str.to_s)
      rescue Date::Error
        @bill.closed_on
      end.clamp(window_start, @bill.closed_on)
      Current.account.transactions.create!(
        created_by: Current.user, credit_card: @bill.credit_card,
        merchant: merchant.to_s.strip.presence || t("card_bills.review.add_line.default_merchant"),
        direction: "expense", status: "posted", confirmed_at: Time.current, source: "manual",
        amount_cents: amount, occurred_on: occurred,
        billing_month: @bill.billing_month, billing_month_manual: true)
      true
    end
    return redirect_to review_card_bill_path(@bill), alert: t("card_bills.pay.invalid_amount") if created.zero?
    redirect_to review_card_bill_path(@bill), notice: t(".added")
  end

  # Cancel the conferência: roll back everything the review did (moves return, adjustment
  # rows are deleted — founder rule 2026-07-22c), forget the informed value, back home.
  def clear_stated
    @bill.rollback_review!
    redirect_to card_bill_path(@bill), notice: t(".cleared")
  end

  # One-click delta row so computed == stated — a normal, DELETABLE card transaction
  # (deleting it is the rollback; same philosophy as the bank-account saldo adjustment).
  # Bank higher → an expense the user missed; bank lower → a credit weighing negative.
  def adjust
    return redirect_to card_bill_path(@bill) if @bill.stated_total_cents.nil?
    delta = @bill.stated_total_cents - @bill.our_total_cents
    return redirect_to card_bill_path(@bill) if delta.zero?
    row = Current.account.transactions.create!(
      created_by: Current.user, credit_card: @bill.credit_card,
      merchant: t("card_bills.review.adjustment_merchant"),
      direction: (delta.positive? ? "expense" : "income"),
      status: "posted", confirmed_at: Time.current, source: "manual",
      amount_cents: delta.abs, occurred_on: @bill.closed_on,
      billing_month: @bill.billing_month, billing_month_manual: true)
    @bill.log_review!("kind" => "adjust", "id" => row.id)
    signed = "#{delta.positive? ? "+" : "−"}#{helpers.brl(delta.abs)}"
    redirect_to card_bill_path(@bill), notice: t(".adjusted", amount: signed)
  end

  # The left-behind batch move: each picked row goes to the NEXT fatura via the existing
  # sticky manual-move (recompute passes already respect billing_month_manual). A partial
  # move lands back on the review page — the remaining difference is still resolvable
  # there (move some AND adjust the rest, founder rule 2026-07-22c).
  def carry_over
    rows = @bill.credit_card.family_transactions.posted.kept
                .where(billing_month: @bill.billing_month, id: Array(params[:transaction_ids]))
    return redirect_to card_bill_path(@bill), alert: t(".none") if rows.none?
    moved = rows.map { |row| { "id" => row.id, "manual_was" => row.billing_month_manual } }
    rows.each { |row| row.update!(billing_month: @bill.billing_month >> 1, billing_month_manual: true) }
    @bill.log_review!("kind" => "move", "rows" => moved)
    destination = @bill.divergence_pending? ? review_card_bill_path(@bill) : card_bill_path(@bill)
    redirect_to destination, notice: t(".moved", count: rows.size)
  end

  # Records a parcelamento de fatura contracted with the bank (founder 2026-07-22d/e).
  # The BANK's numbers verbatim (count + parcela from the bank's app, financed prefilled
  # with our remainder but editable); parcels become derived lines on the next faturas
  # via CreditCard#bill_cents — never rows, so unfinance (destroy) is the whole rollback.
  # The entrada rides the same form: it IS this bill's payment (a normal Pay transfer
  # from the chosen account); blank when it was already recorded via Pagar.
  def finance
    return redirect_to card_bill_path(@bill) if @bill.paid?
    financing = @bill.build_financing(
      account:            @bill.account,
      installments_count: params[:installments_count].to_i,
      installment_cents:  Money.to_cents(params[:installment_reais]).to_i,
      financed_cents:     Money.to_cents(params[:financed_reais]).to_i,
      first_charge_month: @bill.billing_month >> 1)
    return redirect_to card_bill_path(@bill), alert: t(".invalid") unless financing.valid?
    ActiveRecord::Base.transaction do
      financing.save!
      entrada = Money.to_cents(params[:entrada_reais]).to_i
      if entrada.positive?
        payment = CardBills::Pay.call(@bill, amount_cents: entrada, paid_on: Date.current,
                                      bank_account: source_account, created_by: Current.user)
        financing.update!(entrada_transaction: payment)
      end
    end
    redirect_to card_bill_path(@bill), notice: t(".financed", count: financing.installments_count)
  end

  # Cancel the parcelamento record: parcels vanish from future bills, the plain carryover
  # behavior returns on its own (everything downstream is derived) — and the entrada the
  # form posted is reversed too (founder 2026-07-22f: cancel rolls back EVERYTHING the
  # form did; a payment recorded via Pagar beforehand is not the form's and stays).
  def unfinance
    financing = @bill.financing
    entrada = financing&.entrada_transaction
    ActiveRecord::Base.transaction do
      entrada.reverse! if entrada&.posted? && !entrada.soft_deleted?
      financing&.destroy!
    end
    notice = entrada ? t(".unfinanced_with_entrada") : t(".unfinanced")
    redirect_to card_bill_path(@bill), notice: notice
  end

  private
    def set_bill
      @bill = Current.account.card_bills.includes(credit_card: :institution).find(params[:id])
    end

    # Blank = "outra conta (não cadastrada)" — P0 #4, the source-less payment.
    def source_account
      Current.account.bank_accounts.kept.find_by(id: params[:bank_account_id])
    end

    def paid_on
      Date.iso8601(params[:paid_on].to_s)
    rescue Date::Error
      Date.current
    end

    # Paying from the card_due banner dismisses it in the same tap (the occurrences idiom).
    def dismiss_notification
      return if params[:notification_id].blank?
      Current.user.notifications.where(account: Current.account)
             .find_by(id: params[:notification_id])&.dismiss!
    end
end
