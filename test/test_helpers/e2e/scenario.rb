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

    # solo_basic + caixinha + 3 trailing full months + current month, calibrated
    # (see .plans/e2e/02 §3): Mercado 88,3% warn · Restaurantes 108% breach ·
    # Transporte exactly 80% · Lazer 79,997% (no warn) · Vestuário median R$ 420,00 ·
    # guardado R$ 300,00/month. Self-checks at build time.
    def history_calibrated(**)
      solo_basic
      @instruments[:caixinha] = account.bank_accounts.create!(
        institution: institution("260"), nickname: "Caixinha", kind: "savings", created_by: owner)

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

    # solo_basic + caixinha + commitments arranged around the traveled "today"
    # (see .plans/e2e/02 §3): Condomínio due today+1 (default lead) · Luz due today−2 unpaid
    # (inside 3-day overdue grace) · Água due today−5 unpaid (outside grace) · card closing
    # tomorrow · Freela income expected today+1. Two months of paid history behind them.
    def reminders_due(**)
      solo_basic
      @instruments[:caixinha] = account.bank_accounts.create!(
        institution: institution("260"), nickname: "Caixinha", kind: "savings", created_by: owner)
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

    # ── building blocks (also for per-test tweaks) ───────────────────────────────────────

    def expense(merchant:, category:, instrument:, cents:, on:, by: owner, source: "manual")
      attrs = {
        merchant: merchant, direction: "expense", status: "posted", source: source,
        amount_cents: cents, occurred_on: on, confirmed_at: on.in_time_zone,
        created_at: on.in_time_zone, category: self.category(category),
        category_source: "user", created_by: by
      }
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
