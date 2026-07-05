# The hub's read model (R3). A plain PORO — no table, no cache — that is the single owner of
# every zone C/D figure, the WhatsApp `query` answers, and the sparkline points. Nothing here
# is stored (pure record); everything composes over posted_in(month) plus the schedule
# definitions. One formula, three modes: projection terms (⏳) exist for current/future and are
# dropped for past. See .plans/transactions/01-domain-model.md §7.
class MonthSummary
  attr_reader :user, :month

  def initialize(user, month)
    @user  = user
    @month = month.beginning_of_month
  end

  # :past | :current | :future — vs today in America/Sao_Paulo.
  def mode
    today = Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month
    return :past   if @month < today
    return :future if @month > today
    :current
  end

  def projecting? = mode != :past

  # §7.3 — entradas: posted incomes + expected income, counted once.
  def entradas_cents = posted_incomes_cents + expected_incomes_cents

  # §7.4 — saídas: posted bank expenses + projected debit commitments.
  def saidas_cents = posted_expenses_cents + projected_debit_cents

  # §7.2 Σ over the user's cards — the composed bill figure (posted + card-commitment projection).
  def faturas_cents = bill_totals.values.sum

  # §7.5 — guardado: transfers landing in a savings account this month (gross).
  def guardado_cents
    return 0 if savings_account_ids.empty?
    posted.where(direction: "transfer", transfer_to_bank_account_id: savings_account_ids).sum(:amount_cents)
  end

  # §7.6 — THE number (sobra): blue when ≥ 0, red when < 0.
  def remaining_cents = entradas_cents - saidas_cents - faturas_cents - guardado_cents

  # §7.7 — a pagar no mês.
  def a_pagar_cents = faturas_cents + projected_debit_cents

  # §7.2 — { credit_card => cents } composed bill figure per card.
  def bill_totals
    @bill_totals ||= user.credit_cards.index_with { |card| card.bill_cents(@month) }
  end

  # §7.1 — { bank_account_id => cents|nil } derived balance ("now", month-independent).
  def account_balances
    @account_balances ||= bank_accounts.index_by(&:id).transform_values { |a| derived_balance(a) }
  end

  # The "Guardado" total tile figure: Σ §7.1 balances of savings accounts.
  def guardado_total_cents
    bank_accounts.select(&:savings?).sum { |a| account_balances[a.id].to_i }
  end

  def accounts_total_cents
    bank_accounts.sum { |a| account_balances[a.id].to_i }
  end

  def in_the_blue? = remaining_cents >= 0

  private
    def posted = user.transactions.posted_in(@month)

    def bank_accounts = @bank_accounts ||= user.bank_accounts.includes(:institution).order(:created_at).to_a

    def savings_account_ids = @savings_account_ids ||= bank_accounts.select(&:savings?).map(&:id)

    # §7.3 — a card income is an estorno (lives inside §7.2), never here.
    def posted_incomes_cents
      posted.where(direction: "income", credit_card_id: nil).sum(:amount_cents)
    end

    def expected_incomes_cents
      return 0 unless projecting?
      user.incomes.active.reject { |i| income_received?(i) }.sum(&:amount_cents)
    end

    # §7.4 — card spend settles through §7.2; count the row AND its fatura would double-count.
    def posted_expenses_cents
      posted.where(direction: "expense", credit_card_id: nil).sum(:amount_cents)
    end

    def projected_debit_cents
      return 0 unless projecting?
      debit_commitments.select { |c| c.active_in?(@month) && !c.paid_in?(@month) }.sum(&:amount_cents)
    end

    def debit_commitments
      @debit_commitments ||= user.commitments.active.where.not(bank_account_id: nil).to_a
    end

    # §7.3 counts-once: a linked receipt (income_id) OR an unlinked posted deposit on the
    # income's account within ±10% of its amount marks it received. Greedy — each unlinked row
    # claims at most one income.
    def income_received?(income)
      return true if income.received_in?(@month)
      unlinked_income_rows.any? do |row|
        row.bank_account_id == income.bank_account_id &&
          (row.amount_cents - income.amount_cents).abs <= (income.amount_cents / 10)
      end
    end

    def unlinked_income_rows
      @unlinked_income_rows ||= posted.where(direction: "income", income_id: nil, credit_card_id: nil).to_a
    end

    def derived_balance(account)
      return nil unless account.balance_informed?
      since = account.balance_anchored_at || account.updated_at
      base  = user.transactions.posted.where("transactions.created_at > ?", since)
      account.balance_cents +
        base.where(direction: "income",   bank_account_id: account.id).sum(:amount_cents) -
        base.where(direction: "expense",  bank_account_id: account.id).sum(:amount_cents) -
        base.where(direction: "transfer", bank_account_id: account.id).sum(:amount_cents) +
        base.where(direction: "transfer", transfer_to_bank_account_id: account.id).sum(:amount_cents)
    end
end
