class DashboardController < AppController
  def show
    @bank_accounts = Current.user.bank_accounts.includes(:institution).order(:created_at)
    @credit_cards  = Current.user.credit_cards.includes(:institution).order(:created_at)

    @total_balance_cents = @bank_accounts.sum { _1.balance_cents.to_i }
    @total_limit_cents   = @credit_cards.sum { _1.credit_limit_cents.to_i }
    @total_bill_cents    = @credit_cards.sum { _1.current_bill_cents.to_i }
    # Sum the per-card available (nil for limitless cards → 0), mirroring the per-card view —
    # a card with a bill but no limit must not eat into other cards' available credit.
    @total_available_cents = @credit_cards.sum { _1.available_cents.to_i }
  end
end
