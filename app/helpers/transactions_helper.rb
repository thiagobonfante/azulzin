module TransactionsHelper
  # The user's accounts/cards, loaded once per render for the instrument picker.
  def inbox_bank_accounts
    @inbox_bank_accounts ||= Current.user.bank_accounts.includes(:institution).order(:created_at)
  end

  def inbox_credit_cards
    @inbox_credit_cards ||= Current.user.credit_cards.includes(:institution).order(:created_at)
  end

  # Grouped <optgroup> options (accounts, then cards) for the instrument <select>.
  def instrument_option_groups
    [ [ t("app.nav.accounts"), inbox_bank_accounts.map { |a| [ a.display_name, "bank_account-#{a.id}" ] } ],
      [ t("app.nav.cards"),    inbox_credit_cards.map  { |c| [ c.display_name, "credit_card-#{c.id}" ] } ] ]
  end

  # The token matching a transaction's current instrument (for the select's selected value).
  def current_instrument_token(txn)
    return "bank_account-#{txn.bank_account_id}" if txn.bank_account_id
    return "credit_card-#{txn.credit_card_id}"   if txn.credit_card_id

    nil
  end

  # daisyUI badge class for a transaction status, so the inbox reads at a glance.
  def transaction_status_badge(status)
    { "posted"               => "badge-success",
      "pending_review"       => "badge-ghost",
      "needs_confirmation"   => "badge-warning",
      "needs_clarification"  => "badge-warning",
      "needs_disambiguation" => "badge-warning" }.fetch(status, "badge-ghost")
  end
end
