module E2E
  # One scenario = one account = one test. Packs seed through the SAME service objects
  # production uses (Accounts::Bootstrap, onboard!, add_member!, MarkReceived, MarkPaid …)
  # with FIXED calibrated cents — no jitter, no Random. Build packs *inside* travel_to:
  # all dates are relative to the traveled "now" (DemoSeed's evergreen style).
  # See .plans/e2e/02.
  class Scenario
    PASSWORD = "e2e-password"

    attr_reader :account, :owner, :members, :incomes

    def self.build(pack = :bare, **args)
      scenario = new
      scenario.public_send(pack, **args)
      yield scenario if block_given?
      scenario
    end

    def initialize
      @n = Seq.next
      @members = []
      @instruments = {}
      @incomes = []
    end

    # ── identity ─────────────────────────────────────────────────────────────────────────

    def jid(user = owner) = "#{user.phone}@c.us"
    def partner           = (members - [ owner ]).first

    # ── named instruments ────────────────────────────────────────────────────────────────

    def itau         = @instruments.fetch(:itau)
    def nubank_card  = @instruments.fetch(:nubank_card)
    def caixinha     = @instruments.fetch(:caixinha)
    def partner_card = @instruments.fetch(:partner_card)

    def category(name) = account.categories.kept.find_by!(name: name)

    # ── packs ────────────────────────────────────────────────────────────────────────────

    # Confirmed owner + solo account + default pt-BR categories. No instruments, no history.
    def bare(**)
      @owner = new_user("Ana")
      @account = Accounts::Bootstrap.call(@owner)
      @owner.reload.onboard!
      @account.update!(name: "E2E #{@n}")
      @members = [ @owner ]
      self
    end

    # bare + Itaú checking + Nubank card (due 10 / closes the 3rd) + salary R$ 5.000,00 day 5.
    def solo_basic(**)
      bare
      @instruments[:itau] = account.bank_accounts.create!(
        institution: institution("341"), nickname: "Itaú E2E", created_by: owner)
      @instruments[:nubank_card] = account.credit_cards.create!(
        institution: institution("260"), bill_due_day: 10, closing_offset_days: 7,
        credit_limit_cents: 650_000, created_by: owner)
      @incomes << account.incomes.create!(name: "Salário", bank_account: itau,
                                          amount_cents: 500_000, schedule_day: 5, created_by: owner)
      self
    end

    # Decorator: verified WhatsApp identity (+ optional push consent). The sidecar
    # "connected" state is per-test (wa_connect!), not seeded here.
    def wa_verified!(user = owner, consent: false)
      user.verify_whatsapp!(jid(user))
      user.notification_prefs.update!(whatsapp_consent: true) if consent
      self
    end

    # solo_basic + a second member (same row Invitations::Accept mints), both WA-verified.
    def couple(**)
      solo_basic
      other = new_user("Rafael")
      account.add_member!(other)
      other.reload.onboard!
      @members << other
      @instruments[:partner_card] = account.credit_cards.create!(
        institution: institution("341"), bill_due_day: 10, closing_offset_days: 7,
        credit_limit_cents: 800_000, created_by: other)
      wa_verified!(owner)
      wa_verified!(other)
      self
    end

    def add_caixinha!
      @instruments[:caixinha] ||= account.bank_accounts.create!(
        institution: institution("260"), nickname: "Caixinha", kind: "savings", created_by: owner)
      self
    end

    # solo_basic + caixinha + 3 trailing full months + current month, calibrated
    # (see .plans/e2e/02 §3): Mercado 88,3% warn · Restaurantes 108% breach ·
    # Transporte exactly 80% · Lazer 79,997% (no warn) · Vestuário median R$ 420,00 ·
    # guardado R$ 300,00/month. Self-checks at build time.
    def history_calibrated(**)
      solo_basic
      add_caixinha!

      { "Mercado" => 150_000, "Restaurantes" => 60_000, "Transporte" => 45_000,
        "Lazer" => 35_000 }.each { |name, cents| category(name).update!(monthly_budget_cents: cents) }

      vestuario = [ 40_000, 42_000, 410_000 ]   # oldest → newest; median 42_000
      past_months.each_with_index do |month, i|
        receive_income(month)
        expense(merchant: "Supermercado E2E", category: "Mercado",      instrument: itau, cents: 100_000, on: month + 7)
        expense(merchant: "Restaurante E2E",  category: "Restaurantes", instrument: itau, cents: 50_000,  on: month + 9)
        expense(merchant: "Posto E2E",        category: "Transporte",   instrument: itau, cents: 30_000,  on: month + 11)
        expense(merchant: "Cinema E2E",       category: "Lazer",        instrument: itau, cents: 20_000,  on: month + 13)
        expense(merchant: "Loja E2E",         category: "Vestuário",    instrument: itau, cents: vestuario.fetch(i), on: month + 15)
        stash(30_000, on: month)
      end

      receive_income(this_month)
      @income_history_seeded = true   # keeps add_active_goal! from double-receiving
      [ # Current-month calibration — FIXED amounts, bank account only:
        [ "Supermercado E2E", "Mercado",      78_400 ],   # ┐
        [ "Hortifruti E2E",   "Mercado",      34_600 ],   # ├ 132_500 = 88,3% of 150_000 → WARN
        [ "Padaria E2E",      "Mercado",      19_500 ],   # ┘
        [ "Restaurante E2E",  "Restaurantes", 38_900 ],   # ┐ 64_780 = 108,0% of 60_000 → BREACH
        [ "Pizzaria E2E",     "Restaurantes", 25_880 ],   # ┘
        [ "Posto E2E",        "Transporte",   36_000 ],   # exactly 80,000% → WARN (>= boundary)
        [ "Cinema E2E",       "Lazer",        27_999 ]    # 79,997% → silent (one cent under)
      ].each_with_index do |(merchant, cat, cents), i|
        expense(merchant: merchant, category: cat, instrument: itau, cents: cents,
                on: [ today - (i % 5), this_month ].max)
      end
      stash(30_000, on: this_month)

      itau.update!(balance_cents: 250_000)
      caixinha.update!(balance_cents: 520_000)
      verify_calibration!
      self
    end

    # The "Hoje" two-day window (WEB-REC-*): the founder's canonical day — PIX R$ 100,00 no
    # débito + two card swipes of R$ 50,00 riding NEXT month's fatura (the anchor day 20 is
    # past the card's closing day 3) — plus R$ 84,90 yesterday. Self-checks the split and the
    # future-fatura shape at build time.
    def recent_days(**)
      solo_basic
      expense(merchant: "Pix Farmácia",         category: "Saúde",        instrument: itau,        cents: 10_000, on: today)
      expense(merchant: "Padoca",               category: "Restaurantes", instrument: nubank_card, cents: 5_000,  on: today)
      expense(merchant: "Uber",                 category: "Transporte",   instrument: nubank_card, cents: 5_000,  on: today)
      expense(merchant: "Supermercado Zaffari", category: "Mercado",      instrument: itau,        cents: 8_490,  on: today - 1)
      verify_recent_calibration!
      self
    end

    # solo_basic + purchases straddling the card closing (previous month, so they exist on
    # any anchor day) + a 10× R$ 349,90 installment riding the fatura.
    def cards_billing(**)
      solo_basic
      close_day = nubank_card.bill_due_day - nubank_card.closing_offset_days   # the 3rd
      prev = this_month << 1
      expense(merchant: "Na Data de Corte",  category: "Outros", instrument: nubank_card,
              cents: 10_000, on: prev + (close_day - 1))       # ON closing day → prev cycle's bill
      expense(merchant: "Depois do Corte",   category: "Outros", instrument: nubank_card,
              cents: 20_000, on: prev + close_day)             # day after → next cycle's bill
      account.commitments.create!(
        kind: "installment", name: "Notebook", credit_card: nubank_card,
        category: category("Outros"), amount_cents: 34_990, total_cents: 349_900,
        installments_count: 10, starts_on: prev, created_by: owner, created_at: prev.in_time_zone)
      self
    end

    # solo_basic + a CLOSED, unpaid fatura for the anchor month (BILL packs): calibrated
    # 125_000¢ = 60_000 + 50_000 mid-cycle + 15_000 ON the closing edge (the BILL-05
    # left-behind candidate — closest to closing, floats to the top of the picker).
    # Itaú balance R$ 2.500,00 anchors derived-balance assertions. Card due day 10 /
    # closes the 3rd ⇒ at the anchor (the 20th) the bill is closed and already past due.
    def bill_closed(**)
      solo_basic
      close_day = nubank_card.bill_due_day - nubank_card.closing_offset_days   # the 3rd
      prev = this_month << 1
      expense(merchant: "Mercado Grande",    category: "Mercado", instrument: nubank_card,
              cents: 60_000, on: prev + 14)
      expense(merchant: "Farmácia Central",  category: "Saúde",   instrument: nubank_card,
              cents: 50_000, on: prev + 19)
      expense(merchant: "Na Borda do Corte", category: "Outros",  instrument: nubank_card,
              cents: 15_000, on: this_month + (close_day - 1))   # ON the closing date → this bill
      itau.update!(balance_cents: 250_000)
      bills = CardBills::CloseScan.ensure_for(nubank_card)
      verify_bill_calibration!(bills)
      self
    end

    def closed_bill = nubank_card.card_bills.order(:billing_month).last

    # solo_basic + caixinha + commitments arranged around the traveled "today"
    # (see .plans/e2e/02 §3): Condomínio due today+1 (default lead) · Luz due today−2 unpaid
    # (inside 3-day overdue grace) · Água due today−5 unpaid (outside grace) · card closing
    # tomorrow · Freela income expected today+1. Two months of paid history behind them.
    def reminders_due(**)
      solo_basic
      add_caixinha!
      start = this_month << 2
      day = ->(date) { date.day }

      @bills = {}
      [ [ "Condomínio", 48_000, day.(today + 1), "Moradia" ],
        [ "Luz",        18_500, day.(today - 2), "Contas" ],
        [ "Água",        9_500, day.(today - 5), "Contas" ] ].each do |name, cents, sched, cat|
        @bills[name] = account.commitments.create!(
          kind: "fixed", name: name, bank_account: itau, category: category(cat),
          amount_cents: cents, starts_on: start, schedule_day: sched,
          created_by: owner, created_at: start.in_time_zone)
      end
      # Card closing tomorrow: closing = due − offset ⇒ due = tomorrow's day + 7.
      nubank_card.update!(bill_due_day: day.(today + 8), closing_offset_days: 7)
      expense(merchant: "Compra na Fatura", category: "Outros", instrument: nubank_card,
              cents: 25_000, on: today - 3)
      @incomes << account.incomes.create!(name: "Freela", bank_account: itau,
                                          amount_cents: 120_000, schedule_day: day.(today + 1),
                                          created_by: owner)

      # Two paid months behind, but only occurrences older than a week stay paid — anything
      # due in the last 7 days is deliberately left open so the overdue material (Luz −2d,
      # Água −5d) survives month boundaries.
      [ start, start >> 1, this_month ].each do |month|
        receive_income(month, only: "Salário")
        CommitmentOccurrence.for_month(account, month).each do |occ|
          pay(occ.commitment, month) if occ.due_on < today - 7
        end
      end
      self
    end

    def bill(name) = @bills.fetch(name)

    # solo_basic + caixinha + one ACTIVE purchase goal activated 2 months ago through the
    # REAL Goals::Activate (then backdated, DemoSeed-style). `paid` gives the fraction of
    # each month's parcel saved, oldest→current — [1, 1, 1] on-track, [1, 1, 0.8] ≈93%
    # at-risk, [1, 0.5, 0] =50% off-track. Payday is the salary's day 5, so by mid-month
    # expected = 3 × monthly.
    def goal_active(paid: [ 1, 1, 1 ], **)
      solo_basic
      add_caixinha!
      @goal = add_active_goal!(name: "Carro", paid: paid)
      self
    end

    attr_reader :goal

    # into: each goal needs its OWN caixinha — goals sharing one count each other's
    # transfers as their own progress.
    def add_active_goal!(name:, paid: [ 1, 1, 1 ], target_cents: 2_000_000, into: caixinha)
      ensure_income_history!
      goal = account.goals.new(kind: "purchase", name: name, target_cents: target_cents,
                               initial_saved_cents: 0, target_date: this_month >> 12,
                               status: "draft", created_by: owner)
      goal.baseline = Goals::Analyzer.call(account).to_snapshot
      goal.save!
      result = Goals::Activate.call(goal, template: "recomendado",
                                    bank_account_id: into.id, source_bank_account_id: itau.id)
      raise "goal_active pack: activation failed (#{result.inspect})" unless goal.reload.active?

      start = this_month << 2
      commitment = account.commitments.where(kind: "savings", goal: goal).sole
      goal.update_columns(starts_on: start, activated_at: start.in_time_zone,
                          created_at: start.in_time_zone)
      commitment.update_columns(starts_on: start, created_at: start.in_time_zone)

      monthly = goal.monthly_target_cents
      [ start, start >> 1, this_month ].each_with_index do |month, i|
        ratio = paid.fetch(i)
        next if ratio.zero?
        # A partial month PAYS the occurrence with a smaller amount (MarkPaid amount:) —
        # a raw extra transfer would leave the occurrence unpaid and RiskScan would read
        # the month as red from the still-projected commitment.
        pay(commitment, month, amount: (ratio == 1 ? nil : (monthly * ratio).round))
      end
      goal
    end

    # solo_basic + caixinha + income history + an ACTIVE purchase goal whose frozen plan trims
    # Restaurantes to R$ 400,00 — below the member's R$ 600,00 standing budget. ApplyBudgetCuts
    # writes the trim into the category (goals 06 §3); the member then bumps the budget back to
    # 600 mid-goal, so the goal cap (400) stays the tighter binding limit. Current-month
    # Restaurantes spend R$ 340,00 warns against the 400 cap yet is silent against 600 → the
    # budget_warn_goal path (effective_limit = min(standing, trim)). Self-checked in
    # scenario_packs_test (NT-B-05).
    def goal_cuts(**)
      solo_basic
      add_caixinha!
      ensure_income_history!
      rest  = category("Restaurantes")
      rest.update!(monthly_budget_cents: 60_000)
      start = this_month << 1
      @goal = account.goals.create!(
        kind: "purchase", name: "Carro", target_cents: 2_000_000, target_date: this_month >> 10,
        status: "active", monthly_target_cents: 150_000, starts_on: start,
        activated_at: start.in_time_zone, bank_account: caixinha, created_by: owner, baseline: {},
        plan: { "cuts" => [ { "category_id" => rest.id, "cap_cents" => 40_000 } ] })
      Goals::ApplyBudgetCuts.call(@goal)                   # 60_000 → 40_000, previous snapshotted
      rest.reload.update!(monthly_budget_cents: 60_000)    # member raises it back; the goal cap still pins alerts
      expense(merchant: "Restaurante Meta E2E", category: "Restaurantes", instrument: itau,
              cents: 34_000, on: today)
      self
    end

    # Three trailing months of received salary — the Analyzer baseline the goal math needs.
    # Guarded so packs/tests can layer goals without double-receiving a month.
    def ensure_income_history!
      return if @income_history_seeded
      past_months.each { |m| receive_income(m) }
      receive_income(this_month)
      @income_history_seeded = true
    end

    # ── building blocks (also for per-test tweaks) ───────────────────────────────────────

    def expense(merchant:, category:, instrument:, cents:, on:, by: owner, source: "manual", method: nil)
      attrs = {
        merchant: merchant, direction: "expense", status: "posted", source: source,
        amount_cents: cents, occurred_on: on, confirmed_at: on.in_time_zone,
        created_at: on.in_time_zone, category: self.category(category),
        category_source: "user", created_by: by
      }
      attrs[:payment_method] = method if method
      attrs[instrument.is_a?(CreditCard) ? :credit_card : :bank_account] = instrument
      account.transactions.create!(**attrs)
    end

    def stash(cents, on:, from: itau)
      account.transactions.create!(
        merchant: "Guardado do mês", direction: "transfer", status: "posted", source: "manual",
        amount_cents: cents, occurred_on: on, confirmed_at: on.in_time_zone,
        created_at: on.in_time_zone, bank_account: from,
        transfer_to_bank_account: caixinha, created_by: owner)
    end

    def receive_income(month, only: nil)
      incomes.each do |income|
        next if only && income.name != only
        on = [ income.expected_on(month), today ].min
        Incomes::MarkReceived.call(income, month, created_by: owner)
               .update_columns(occurred_on: on, created_at: on.in_time_zone)
      end
    end

    def pay(commitment, month, amount: nil)
      occ_due = CommitmentOccurrence.for_month(account, month)
                                    .find { |o| o.commitment == commitment }&.due_on
      Commitments::MarkPaid.call(commitment, month, amount: amount, created_by: owner)
                 .update_columns(occurred_on: occ_due, created_at: occ_due.in_time_zone)
    end

    private

    def new_user(name)
      m = Seq.next
      User.create!(email_address: "e2e-#{m}@example.test", password: PASSWORD,
                   name: "#{name} E2E#{m}", phone: format("5511%09d", 900_000_000 + m),
                   confirmed_at: Time.current)
    end

    def institution(code) = Institution.find_by!(code: code)
    def today             = Date.current
    def this_month        = today.beginning_of_month
    def past_months       = (1..3).map { |i| this_month << i }.reverse

    # recent_days tripwire: the pack's whole point is the exact 100/50/50 split with the card
    # swipes landing on a FUTURE fatura — fail here, named, if billing rules or amounts drift.
    def verify_recent_calibration!
      rows = account.transactions.occurred_between(today - 1, today).to_a
      card = rows.select(&:credit_card_id)
      ok = rows.size == 4 && card.size == 2 && card.sum(&:amount_cents) == 10_000 &&
           card.all? { |r| r.billing_month != r.occurred_on.beginning_of_month }
      unless ok
        raise "recent_days pack lost its calibration: " \
              "#{rows.map { |r| [ r.merchant, r.amount_cents, r.billing_month ] }.inspect}"
      end
    end

    # bill_closed tripwire: exactly ONE closed bill for the anchor month at exactly
    # 125_000¢, unpaid — the frozen cents every BILL test asserts against.
    def verify_bill_calibration!(bills)
      bill = bills.last
      ok = bills.size == 1 && bill&.billing_month == this_month &&
           bill.computed_total_cents == 125_000 && bill.status == "unpaid"
      return if ok
      raise "bill_closed pack lost its calibration: " \
            "#{bills.map { |b| [ b.billing_month, b.computed_total_cents, b.status ] }.inspect}"
    end

    # Cheap tripwire: if service logic changes ever un-calibrate this pack, fail HERE with
    # the calibration named — not in fifty downstream tests (.plans/e2e/02 §4).
    def verify_calibration!
      events = Budgets::Check.call(account, month: this_month, warn_percent: 80, breach_percent: 100)
      by_cat = events.group_by { |e| e[:payload][:category] }
      unless by_cat.dig("Mercado", 0)&.fetch(:kind) == "budget_warn" &&
             by_cat.dig("Restaurantes", 0)&.fetch(:kind) == "budget_breach" &&
             by_cat.dig("Transporte", 0)&.fetch(:kind) == "budget_warn" &&
             !by_cat.key?("Lazer")
        raise "history_calibrated pack lost its band calibration: #{events.inspect}"
      end
      suggested = Budgets::Suggest.call(account)
      vest = suggested[category("Vestuário").id]
      raise "history_calibrated pack lost the median calibration (got #{vest.inspect})" unless vest == 42_000
    end
  end
end
