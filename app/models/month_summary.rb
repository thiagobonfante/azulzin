# The hub's read model (R3). A plain PORO — no table, no cache — that is the single owner of
# every zone C/D figure, the WhatsApp `query` answers, and the sparkline points. Nothing here
# is stored (pure record); everything composes over posted_in(month) plus the schedule
# definitions. One formula, three modes: projection terms (⏳) exist for current/future and are
# dropped for past. See .plans/transactions/01-domain-model.md §7.
class MonthSummary
  attr_reader :account, :month

  def initialize(account, month)
    @account = account
    @month   = month.beginning_of_month
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

  # Saídas as the hero strip shows it: bank/debit outflow + card bills folded into one figure.
  def saidas_total_cents = saidas_cents + faturas_cents

  # §7.5 — guardado: transfers landing in a savings account this month (gross).
  def guardado_cents
    return 0 if savings_account_ids.empty?
    posted.where(direction: "transfer", transfer_to_bank_account_id: savings_account_ids).sum(:amount_cents)
  end

  # §7.6 — THE number (sobra): blue when ≥ 0, red when < 0. A goal contribution ("pay yourself
  # first", .plans/goals 07 §1.3) is subtracted while unpaid via projected_guardado_cents and,
  # once paid, via guardado_cents — the amount moves buckets, so sobra is invariant at pay time.
  def remaining_cents = entradas_cents - saidas_cents - faturas_cents - guardado_cents - projected_guardado_cents

  # §7.7 — a pagar no mês (incl. the still-owed goal contributions — that IS pay-yourself-first).
  def a_pagar_cents = faturas_cents + projected_debit_cents + projected_guardado_cents

  # §7.4 — the still-unpaid debit commitments projected into this month (empty for a past month).
  # The per-commitment rows behind projected_debit_cents; the category bar folds them in by category.
  def projected_debit_commitments
    return [] unless projecting?
    debit_commitments.select { |c| c.active_in?(@month) && !c.paid_in?(@month) }
  end

  # §7.5 (goals 07 §1.3) — the still-unpaid savings-commitment occurrences this month: the
  # "pay yourself first" contributions still owed. A projection term (empty for a past month),
  # mirroring projected_debit_commitments; the hub renders these in blue as "Meta: <name>".
  def projected_guardado_commitments
    return [] unless projecting?
    savings_commitments.select { |c| c.active_in?(@month) && !c.paid_in?(@month) }
  end

  def projected_guardado_cents = projected_guardado_commitments.sum(&:amount_cents)

  # §7.2 — { credit_card => cents } composed bill figure per card. A CLOSED bill row
  # swaps in its effective total (the bank's number when informed — .plans/credit-cards
  # 01 §4.4); open months keep the live query. The previous bill's unpaid remainder rides
  # as the carryover + estimated-encargos term (02 §5) — labeled lines, never rows.
  def bill_totals
    @bill_totals ||= begin
      closed = account.card_bills.where(billing_month: @month).index_by(&:credit_card_id)
      account.credit_cards.kept.roots.index_with do |card|
        base = closed[card.id]&.effective_total_cents || card.bill_cents(@month)
        base + card_carryovers[card]&.fetch(:total_cents).to_i
      end
    end
  end

  # { credit_card => carryover projection | absent } — the labeled lines the bills tile
  # renders under each card (.plans/credit-cards 02 §5).
  def card_carryovers
    @card_carryovers ||= account.credit_cards.kept.roots
                                .index_with { |card| CardBills::Carryover.for(card, @month) }
                                .compact
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

  # §7.3 counts-once: a linked receipt (income_id) OR an unlinked posted deposit on the
  # income's account within ±10% of its amount marks it received. Greedy — each unlinked row
  # claims at most one income. Public: the hub's "A receber" card shows the same status.
  def income_received?(income)
    return true if income.received_in?(@month)
    unlinked_income_rows.any? do |row|
      row.bank_account_id == income.bank_account_id &&
        (row.amount_cents - income.amount_cents).abs <= (income.amount_cents / 10)
    end
  end

  private
    def posted = account.transactions.posted_in(@month)   # posted_in already carries .kept

    def bank_accounts = @bank_accounts ||= account.bank_accounts.kept.includes(:institution).order(:created_at).to_a

    def savings_account_ids = @savings_account_ids ||= bank_accounts.select(&:savings?).map(&:id)

    # §7.3 — a card income is an estorno (lives inside §7.2), never here.
    def posted_incomes_cents
      posted.where(direction: "income", credit_card_id: nil).sum(:amount_cents)
    end

    def expected_incomes_cents
      return 0 unless projecting?
      account.incomes.kept.active.reject { |i| income_received?(i) }.sum(&:amount_cents)
    end

    # §7.4 — card spend settles through §7.2; count the row AND its fatura would double-count.
    def posted_expenses_cents
      posted.where(direction: "expense", credit_card_id: nil).sum(:amount_cents)
    end

    def projected_debit_cents = projected_debit_commitments.sum(&:amount_cents)

    # Savings-kind commitments are excluded here (they're not spending) and projected separately
    # via projected_guardado_cents — .plans/goals 07 §1.3, the sobra-invariance-at-pay-time trap.
    def debit_commitments
      @debit_commitments ||= account.commitments.kept.active.where.not(bank_account_id: nil).where.not(kind: "savings").to_a
    end

    def savings_commitments
      @savings_commitments ||= account.commitments.kept.active.savings.where.not(bank_account_id: nil).to_a
    end

    def unlinked_income_rows
      @unlinked_income_rows ||= posted.where(direction: "income", income_id: nil, credit_card_id: nil).to_a
    end

    # §7.1 lives on the model (BankAccount#derived_balance_cents) so the dashboard and the
    # accounts page show the same figure as the hub.
    def derived_balance(account) = account.derived_balance_cents
end
