class DashboardController < AppController
  include WhatsappActivation

  def show
    prepare_whatsapp_activation
    @bank_accounts = Current.account.bank_accounts.kept.includes(:institution).order(:created_at)
    @credit_cards  = Current.account.credit_cards.kept.includes(:institution).order(:created_at)

    @total_balance_cents = @bank_accounts.sum { _1.derived_balance_cents.to_i }
    @total_limit_cents   = @credit_cards.sum { _1.credit_limit_cents.to_i }
    @total_bill_cents    = @credit_cards.sum { _1.open_bill_cents }
    # Sum the per-card available (nil for limitless cards → 0), mirroring the per-card view —
    # a card with a bill but no limit must not eat into other cards' available credit.
    @total_available_cents = @credit_cards.sum { _1.available_cents.to_i }
  end
end
