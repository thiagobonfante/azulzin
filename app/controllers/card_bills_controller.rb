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
      stated_total_cents:   optional_cents(:stated_total_reais),
      stated_minimum_cents: optional_cents(:stated_minimum_reais),
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

  # Informing (or correcting) the bank's number from the bill page (.plans/credit-cards 03 §1).
  def update
    stated = Money.to_cents(params[:stated_total_reais]).to_i
    return redirect_to card_bill_path(@bill), alert: t("card_bills.pay.invalid_amount") unless stated.positive?
    @bill.update!(stated_total_cents: stated)
    redirect_to card_bill_path(@bill), notice: t(".stated_saved")
  end

  # The left-behind batch move: each picked row goes to the NEXT fatura via the existing
  # sticky manual-move (recompute passes already respect billing_month_manual).
  def carry_over
    rows = @bill.credit_card.family_transactions.posted.kept
                .where(billing_month: @bill.billing_month, id: Array(params[:transaction_ids]))
    return redirect_to card_bill_path(@bill), alert: t(".none") if rows.none?
    rows.each { |row| row.update!(billing_month: @bill.billing_month >> 1, billing_month_manual: true) }
    redirect_to card_bill_path(@bill), notice: t(".moved", count: rows.size)
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

    # The collapsed "valor no banco" disclosure — stored silently in phase 1 (P1 note:
    # divergence actions arrive in phase 2). Blank input never clears a stored value.
    def optional_cents(key)
      cents = Money.to_cents(params[key])
      cents if cents.to_i.positive?
    end

    # Paying from the card_due banner dismisses it in the same tap (the occurrences idiom).
    def dismiss_notification
      return if params[:notification_id].blank?
      Current.user.notifications.where(account: Current.account)
             .find_by(id: params[:notification_id])&.dismiss!
    end
end
