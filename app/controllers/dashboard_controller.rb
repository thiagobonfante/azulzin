class DashboardController < AppController
  include WhatsappActivation

  def show
    prepare_whatsapp_activation
    @notifications = Notification.dashboard_for(Current.user, Current.account)
    # The pending-review tray (R8), mirrored from the transactions hub — WA parks land here.
    @pending = Current.account.transactions.includes(:bank_account, :credit_card).pending_inbox.order(created_at: :desc)
    @bank_accounts = Current.account.bank_accounts.kept.includes(:institution).order(:created_at)
    @credit_cards  = Current.account.credit_cards.kept.includes(:institution).order(:created_at)

    @total_balance_cents = @bank_accounts.sum { _1.derived_balance_cents.to_i }
    @total_limit_cents   = @credit_cards.sum { _1.credit_limit_cents.to_i }
    @total_bill_cents    = @credit_cards.sum { _1.open_bill_cents }
    # Sum the per-card available (nil for limitless cards → 0), mirroring the per-card view —
    # a card with a bill but no limit must not eat into other cards' available credit.
    @total_available_cents = @credit_cards.sum { _1.available_cents.to_i }

    # "Hoje" tile (.plans/today-expenses §8): today's spend by PURCHASE date — same predicate
    # the recent view sums (posted+kept expenses occurred today), so both figures always agree.
    today = Date.current.in_time_zone("America/Sao_Paulo").to_date
    @today_spent_cents = Current.account.transactions.spend.where(occurred_on: today).sum(:amount_cents)
  end
end
