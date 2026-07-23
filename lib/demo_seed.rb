# Builds the fully fictional demo household — "Família Andrade": Marina (owner) + Rafael
# (member) sharing one account, with 4 trailing full months of history plus the current month
# so far. Everything is computed relative to Date.current (EVERGREEN — no hardcoded months),
# and all randomness comes from Random.new(42), so two runs on the same day produce identical
# data. WIPES + recreates both users on every run, so it is safely re-seedable.
#
# Shared by dev:seed_demo and prod:seed_demo — the only difference between those tasks is the
# environment guard; the seeded household (emails, password, account name) is identical, so the
# prod demo logs in with the same credentials once its emails are on the allowlist.
#
# What the seed calibrates (and the verification block asserts):
#   • Budgets::Suggest has ≥4 categories with trailing-3-month medians (the "sugerir" chip).
#   • Budget bands for the current month, on BANK-account spend only (card spend buckets by
#     billing_month, which shifts with the closing rule — bank rows bucket by calendar month,
#     so the calibration is exact whatever day the seed runs):
#       – Mercado:      R$ 1.325,00 of R$ 1.500,00 (88,3%) → WARN band [80%, 100%)
#       – Restaurantes: R$   647,80 of R$   600,00 (108,0%) → BREACH (≥100%)
#     No commitment carries a budgeted category, so unpaid bills folding into
#     Budgets::Actuals can never disturb these two figures.
#   • Reminders::Scan(from: today, to: today+3) always yields ≥1 event: "Condomínio" gets a
#     RELATIVE schedule_day (today+2, clamped to 28) so a bill is due inside the window on
#     any run date; card subscriptions (due end of month) cover the clamped days 29–31.
#   • Bank balances are set LAST: BankAccount#derived_balance_cents adds rows created after
#     the balance anchor, so anchoring after all history rows makes derived = stored.
module DemoSeed
  # The canonical demo password is demo1234 (User validates password length ≥ 8, so demo123
  # is one character short and fails validation).
  DEFAULT_PASSWORD = "demo1234"
  EMAILS           = { marina: "marina@azulzin.dev", rafael: "rafael@azulzin.dev" }.freeze
  ACCOUNT_NAME     = "Família Andrade"

  def self.run(password: DEFAULT_PASSWORD)
    emails = EMAILS

    emails.each_value do |email|
      next unless (existing = User.find_by(email_address: email))
      puts "Wiping #{email} (user ##{existing.id}) and all its financial data…"
      existing.account&.destroy!   # LGPD cascade lives on Account; also drops memberships
      existing.destroy!
    end

    Institution.load_registry!
    inst = { itau: Institution.find_by!(code: "341"), nubank: Institution.find_by!(code: "260") }

    # ── The household: Marina owns the account, Rafael joins it (the invitation-acceptance
    #    path mints exactly this membership row — see Invitations::Accept) ─────────────────
    marina = User.create!(email_address: emails[:marina], password: password, name: "Marina Andrade",
                          phone: "5511987654321", confirmed_at: Time.current)
    account = Accounts::Bootstrap.call(marina)
    marina.reload            # refresh has_one :account before onboard!
    marina.onboard!          # seeds the default pt-BR categories into the account
    account.update!(name: ACCOUNT_NAME)

    rafael = User.create!(email_address: emails[:rafael], password: password, name: "Rafael Andrade",
                          phone: "5511976543210", confirmed_at: Time.current)
    account.add_member!(rafael)
    rafael.reload
    rafael.onboard!          # categories already seeded → just skips the wizard

    # Verified WhatsApp identity for both (exercises the sender gate in dev). Consent stays
    # default-false: no NotificationPreference rows are created here.
    marina.verify_whatsapp!("5511987654321@c.us")
    rafael.verify_whatsapp!("5511976543210@c.us")

    # ── Evergreen time anchors + deterministic randomness ────────────────────────────────
    today       = Date.current
    this_month  = today.beginning_of_month
    past_months = (1..4).map { |i| this_month << i }.reverse   # 4 trailing FULL months, oldest first
    rng         = Random.new(42)
    jitter      = ->(base) { base + rng.rand(-(base / 5)..(base / 5)) }   # ±20%, integer cents

    # ── Instruments (balances informed at the END — see header) ──────────────────────────
    bank_accounts = {
      itau:     account.bank_accounts.create!(institution: inst[:itau],   nickname: "Itaú (Marina)",   created_by: marina),
      nubank:   account.bank_accounts.create!(institution: inst[:nubank], nickname: "Nubank (Rafael)", created_by: rafael),
      savings: account.bank_accounts.create!(institution: inst[:nubank], nickname: "Caixinha", kind: "savings", created_by: marina)
    }
    # Both cards billing-configured: due day 10, default closing offset 7 ⇒ fatura closes on
    # the 3rd, so purchases dated day ≥ 4 of month M−1 land on M's bill.
    cartoes = {
      nubank: account.credit_cards.create!(institution: inst[:nubank], bill_due_day: 10, credit_limit_cents: 650_000, created_by: rafael),
      itau:   account.credit_cards.create!(institution: inst[:itau],   bill_due_day: 10, credit_limit_cents: 800_000, created_by: marina)
    }

    # ── Categories: reuse the onboarding defaults by name (never a parallel set) ─────────
    categories = account.categories.kept.index_by(&:name)
    { "Mercado" => 150_000, "Restaurantes" => 60_000, "Transporte" => 45_000,
      "Lazer" => 35_000, "Vestuário" => 25_000 }.each do |name, cents|
      categories.fetch(name).update!(monthly_budget_cents: cents)
    end
    # Moradia, Contas, Saúde, Assinaturas, Outros… stay UNBUDGETED (suggest chip testable there).

    # ── Incomes: both salaries land on day 5 ─────────────────────────────────────────────
    incomes = [
      account.incomes.create!(name: "Salário Marina", bank_account: bank_accounts[:itau],
                              amount_cents: 650_000, schedule_day: 5, created_by: marina),
      account.incomes.create!(name: "Salário Rafael", bank_account: bank_accounts[:nubank],
                              amount_cents: 420_000, schedule_day: 5, created_by: rafael)
    ]

    # ── Commitments (created_at backdated to starts_on: occurrences before the creation
    #    month render presumed-paid, which would double-count the real payments below) ────
    start = past_months.first
    nudge_day = [ today.day + 2, 28 ].min   # the evergreen reminder guarantee (see header)
    bills = {}
    [
      # name          account   category    cents    day  owner
      [ "Aluguel",    :itau,   "Moradia",  220_000,  10,  marina ],
      [ "Condomínio", :itau,   "Moradia",   48_000,  nudge_day, marina ],
      [ "Luz",        :itau,   "Contas",    18_500,  12,  marina ],
      [ "Água",       :itau,   "Contas",     9_500,  12,  marina ],
      [ "Internet",   :itau,   "Contas",    11_990,  15,  marina ],
      [ "Academia",   :nubank, "Saúde",     12_990,   8,  rafael ]
    ].each do |name, acct, cat, cents, day, owner|
      bills[name] = account.commitments.create!(
        kind: "fixed", name: name, bank_account: bank_accounts[acct], category: categories.fetch(cat),
        amount_cents: cents, starts_on: start, schedule_day: day,
        created_by: owner, created_at: start.in_time_zone)
    end
    [
      [ "Netflix", :nubank, 4_490, rafael ],
      [ "Spotify", :nubank, 2_190, rafael ],
      [ "iCloud",  :itau,     490, marina ]
    ].each do |name, card, cents, owner|
      account.commitments.create!(
        kind: "subscription", name: name, credit_card: cartoes[card],
        category: categories.fetch("Assinaturas"), amount_cents: cents, starts_on: start,
        created_by: owner, created_at: start.in_time_zone)
    end
    account.commitments.create!(   # card installment: 10× R$ 349,90 riding the Itaú fatura
      kind: "installment", name: "Notebook", credit_card: cartoes[:itau],
      category: categories.fetch("Outros"), amount_cents: 34_990, total_cents: 349_900,
      installments_count: 10, starts_on: start, created_by: rafael, created_at: start.in_time_zone)
    account.commitments.create!(   # debit installment: 6× R$ 280,00 from the Itaú account
      kind: "installment", name: "Sofá", bank_account: bank_accounts[:itau],
      category: categories.fetch("Moradia"), amount_cents: 28_000, total_cents: 168_000,
      installments_count: 6, schedule_day: 18, starts_on: start, created_by: marina, created_at: start.in_time_zone)
    variable_bills = [ bills["Luz"], bills["Água"] ]   # utility amounts vary month to month

    # ── Shared one-off writer: posted expense, attributed to a real member, backdated so
    #    every history row predates the balance anchor stamped at the end ─────────────────
    members = [ marina, rafael ].cycle
    add_expense = lambda do |merchant, cat, instrument, cents, occurred|
      attrs = {
        merchant: merchant, direction: "expense", status: "posted", source: "manual",
        amount_cents: cents, occurred_on: occurred, confirmed_at: occurred.in_time_zone,
        created_at: occurred.in_time_zone, category: categories.fetch(cat),
        category_source: "user", created_by: members.next
      }
      attrs[instrument.is_a?(CreditCard) ? :credit_card : :bank_account] = instrument
      account.transactions.create!(**attrs)
    end

    # Fictional merchant tables: base amounts are jittered ±20% per month by the seeded rng.
    bank_history = [
      [ "Supermercado Bom Preço",  "Mercado",      bank_accounts[:itau],   41_500 ],
      [ "Hortifruti da Vila",      "Mercado",      bank_accounts[:nubank], 12_300 ],
      [ "Padaria Estrela",         "Mercado",      bank_accounts[:itau],    6_800 ],
      [ "iFood",                   "Restaurantes", bank_accounts[:nubank], 17_400 ],
      [ "Pizzaria Bella Massa",    "Restaurantes", bank_accounts[:itau],   11_200 ],
      [ "Churrascaria Braseiro",   "Restaurantes", bank_accounts[:nubank], 16_900 ],
      [ "Posto Andorinha",         "Transporte",   bank_accounts[:nubank], 21_000 ],
      [ "Uber",                    "Transporte",   bank_accounts[:itau],    7_300 ],
      [ "Drogaria São Jorge",      "Saúde",        bank_accounts[:nubank],  8_900 ],
      [ "Cinema do Shopping",      "Lazer",        bank_accounts[:itau],    9_400 ],
      [ "Lojas Vida & Moda",       "Vestuário",    bank_accounts[:nubank], 15_800 ]
    ]
    card_history = [
      [ "Mercado Pague Menos",     "Mercado",      cartoes[:itau],   23_500 ],
      [ "Sushi Tanaka",            "Restaurantes", cartoes[:nubank], 13_800 ],
      [ "Amazonia Store",          "Outros",       cartoes[:nubank], 11_600 ],
      [ "Livraria Página Viva",    "Educação",     cartoes[:itau],    9_700 ],
      [ "Petshop Rabo Feliz",      "Outros",       cartoes[:nubank], 13_900 ],
      [ "Posto Andorinha",         "Transporte",   cartoes[:itau],   18_600 ]
    ]

    # ── Past months: incomes received, every occurrence paid, one-offs spread around ─────
    receive = lambda do |income, month|
      on = [ income.expected_on(month), today ].min
      Incomes::MarkReceived.call(income, month, created_by: income.created_by)
             .update_columns(occurred_on: on, created_at: on.in_time_zone)
    end
    pay = lambda do |occ, month|
      amount = variable_bills.include?(occ.commitment) ? jitter.(occ.commitment.amount_cents) : nil
      Commitments::MarkPaid.call(occ.commitment, month, amount: amount, created_by: occ.commitment.created_by)
                 .update_columns(occurred_on: occ.due_on, created_at: occ.due_on.in_time_zone)
    end

    past_months.each do |month|
      incomes.each { |income| receive.call(income, month) }
      CommitmentOccurrence.for_month(account, month).each { |occ| pay.call(occ, month) }
      bank_history.each do |merchant, cat, acct, base|
        next if rng.rand(100) < 15   # skip ~15% of visits for month-to-month variety
        add_expense.call(merchant, cat, acct, jitter.(base), month + 2 + rng.rand(0..24))   # day 3–27
      end
      card_history.each do |merchant, cat, card, base|
        next if rng.rand(100) < 15
        # Dated day 4–24 of the PREVIOUS month ⇒ lands on `month`'s fatura (closing = the 3rd).
        add_expense.call(merchant, cat, card, jitter.(base), (month << 1) + 3 + rng.rand(0..20))
      end
      # Monthly stash into the Caixinha — feeds guardado + the surplus_nudge savings path.
      account.transactions.create!(
        merchant: "Guardado do mês", direction: "transfer", status: "posted", source: "manual",
        amount_cents: 30_000, occurred_on: month, confirmed_at: month.in_time_zone,
        created_at: month.in_time_zone, bank_account: bank_accounts[:itau],
        transfer_to_bank_account: bank_accounts[:savings], created_by: marina)
    end

    # ── Current month: incomes in, bills due before today paid, the rest left UNPAID so
    #    Reminders::Scan has material (Condomínio's relative day guarantees ≥1 hit) ───────
    incomes.each { |income| receive.call(income, this_month) }
    CommitmentOccurrence.for_month(account, this_month).each do |occ|
      pay.call(occ, this_month) if occ.due_on < today
    end

    # Budget-band calibration — FIXED amounts (never jittered), bank accounts only, and no
    # other current-month row touches a budgeted category, so the bands hold on any day:
    [
      # Mercado: 78_400 + 34_600 + 19_500 = 132_500 = 88,3% of 150_000 → WARN band
      [ "Supermercado Bom Preço", "Mercado",      bank_accounts[:itau],   78_400 ],
      [ "Hortifruti da Vila",     "Mercado",      bank_accounts[:nubank], 34_600 ],
      [ "Padaria Estrela",        "Mercado",      bank_accounts[:itau],   19_500 ],
      # Restaurantes: 38_900 + 25_880 = 64_780 = 108,0% of 60_000 → BREACH
      [ "iFood",                  "Restaurantes", bank_accounts[:nubank], 38_900 ],
      [ "Pizzaria Bella Massa",   "Restaurantes", bank_accounts[:itau],   25_880 ],
      # Comfortably below the 80% warn line:
      [ "Uber",                   "Transporte",   bank_accounts[:itau],    9_840 ],
      [ "Posto Andorinha",        "Transporte",   bank_accounts[:nubank],  8_000 ],
      [ "Cinema do Shopping",     "Lazer",        bank_accounts[:itau],    8_990 ],
      [ "Lojas Vida & Moda",      "Vestuário",    bank_accounts[:nubank],  4_500 ]
    ].each_with_index do |(merchant, cat, acct, cents), i|
      add_expense.call(merchant, cat, acct, cents, [ today - (i % 5), this_month ].max)
    end
    # Card spend on the CURRENT billing month too (dated day 6–8 of last month ⇒ this fatura);
    # unbudgeted categories only, to keep the calibration above exact.
    [
      [ "Farmácia Preço Justo", "Saúde",  cartoes[:nubank], 6_450 ],
      [ "Petshop Rabo Feliz",   "Outros", cartoes[:itau],  14_200 ],
      [ "Amazonia Store",       "Outros", cartoes[:nubank], 8_760 ]
    ].each_with_index do |(merchant, cat, card, cents), i|
      add_expense.call(merchant, cat, card, cents, (this_month << 1) + 5 + i)
    end
    account.transactions.create!(   # day 1 ⇒ never in the future, whatever day the seed runs
      merchant: "Guardado do mês", direction: "transfer", status: "posted", source: "manual",
      amount_cents: 30_000, occurred_on: this_month, confirmed_at: this_month.in_time_zone,
      created_at: this_month.in_time_zone, bank_account: bank_accounts[:itau],
      transfer_to_bank_account: bank_accounts[:savings], created_by: marina)

    # ── Credit-card bill lifecycle (.plans/credit-cards): the whole story on two cards.
    #    `recent` = the most recently CLOSED cycle whatever day the seed runs; `older` the
    #    one before. Nubank: older PARTIALLY paid (→ carryover + encargos-estimados lines
    #    project onto `recent`), recent closed UNPAID (the pay-CTA notification below).
    #    Itaú: older PAID in full; recent carries a stated bank value exactly ONE
    #    edge-of-closing purchase below computed — the left-behind picker demos in a click. ─
    { "rotativo" => "15.09", "parcelamento" => "9.26" }.each do |kind, rate|
      BcbRate.find_or_create_by!(kind: kind, reference_month: this_month << 1) do |row|
        row.monthly_rate = BigDecimal(rate)
        row.fetched_at   = Time.current
      end
    end

    open_month = cartoes[:nubank].current_open_bill_month
    recent     = open_month << 1
    older      = open_month << 2
    older2     = open_month << 3   # extra Itaú cycle: the parcelamento-de-fatura demo
    edge_cents = 18_990

    # Sub-cards under Rafael's Nubank (04): nicknames ARE the feature. A couple of rows
    # each — one on the recently closed bill (sub-card chips on the bill page), one on the
    # open bill. Default card per member: each spouse's own plastic.
    subs = {
      ifood: account.credit_cards.create!(institution: inst[:nubank], parent_card: cartoes[:nubank],
                                          nickname: "virtual iFood", card_type: "virtual", last4: "7001", created_by: rafael),
      filha: account.credit_cards.create!(institution: inst[:nubank], parent_card: cartoes[:nubank],
                                          nickname: "cartão da filha", last4: "7002", created_by: rafael)
    }
    closing_recent = cartoes[:nubank].closing_date(recent)
    add_expense.call("iFood",             "Restaurantes", subs[:ifood], 3_490, closing_recent - 2)
    add_expense.call("iFood",             "Restaurantes", subs[:ifood], 5_690, closing_recent + 1)
    add_expense.call("Lanchonete Escola", "Restaurantes", subs[:filha], 2_500, closing_recent - 5)
    add_expense.call("Papelaria Central", "Educação",     subs[:filha], 4_200, closing_recent + 1)
    marina.update!(default_credit_card_id: cartoes[:itau].id)
    rafael.update!(default_credit_card_id: cartoes[:nubank].id)
    add_expense.call("Loja na Véspera do Corte", "Outros", cartoes[:itau], edge_cents,
                     cartoes[:itau].closing_date(recent))   # ON the closing date → `recent`'s bill

    CardBills::CloseScan.close(cartoes[:itau], older2)   # the cycle the bank parceled
    cartoes.each_value do |card|
      CardBills::CloseScan.close(card, older)
      CardBills::CloseScan.ensure_for(card)   # fills `recent`; the open month stays a query
    end

    nubank_older  = cartoes[:nubank].card_bills.find_by!(billing_month: older)
    nubank_recent = cartoes[:nubank].card_bills.find_by!(billing_month: recent)
    itau_older    = cartoes[:itau].card_bills.find_by!(billing_month: older)
    itau_recent   = cartoes[:itau].card_bills.find_by!(billing_month: recent)
    itau_financed = cartoes[:itau].card_bills.find_by!(billing_month: older2)

    # Parcelamento de fatura (f6f3013): entrada ~25% via the form's flow, remainder split
    # into 3 fixed parcels (+6% juros, whole reais) riding `older`, `recent` and the open
    # month — bills history shows "parcelada", the hub tile a parcel line. Created BEFORE
    # the later bills are paid/stated so their derived totals already include the parcels.
    down_payment_cents  = itau_financed.our_total_cents / 4 / 100 * 100
    financed_cents = itau_financed.our_total_cents - down_payment_cents
    parcel_cents   = (financed_cents * 106 / 100 / 3 / 100 + 1) * 100
    financing = itau_financed.create_financing!(
      account: account, created_by: marina, installments_count: 3,
      installment_cents: parcel_cents, financed_cents: financed_cents,
      first_charge_month: older2 >> 1)
    down_payment = CardBills::Pay.call(itau_financed, amount_cents: down_payment_cents,
      paid_on: itau_financed.due_on, bank_account: bank_accounts[:itau], created_by: marina)
    down_payment.update_columns(created_at: itau_financed.due_on.in_time_zone)
    financing.update!(down_payment_transaction: down_payment)
    # computing entrada from our_total above cached bill_financings EMPTY on the card —
    # reload so the later pays/stated see the parcels (the per-instance-cache gotcha).
    cartoes[:itau].bill_financings.reload

    pay_bill = lambda do |bill, amount, source, payer|
      CardBills::Pay.call(bill, amount_cents: amount, paid_on: bill.due_on,
                          bank_account: source, created_by: payer)
               .update_columns(created_at: bill.due_on.in_time_zone)
    end
    partial = (nubank_older.effective_total_cents * 2 / 5) / 100 * 100   # ~40%, whole reais
    pay_bill.call(nubank_older, partial, bank_accounts[:nubank], rafael)
    pay_bill.call(itau_older, itau_older.effective_total_cents, bank_accounts[:itau], marina)
    itau_recent.update!(stated_total_cents: itau_recent.computed_total_cents - edge_cents)

    # The dashboard alert both members see: pay CTA deep-linking the nubank `recent` bill —
    # card_due while it hasn't fallen due (seed days 4–9), card_overdue after (the honest kind).
    if nubank_recent.due_on >= today
      [ marina, rafael ].each do |member|
        Notification.record!(user: member, account: account, kind: "card_due",
          subject: cartoes[:nubank], period_key: nubank_recent.due_on,
          payload: { card: cartoes[:nubank].display_name, amount_cents: nubank_recent.effective_total_cents,
                     date: nubank_recent.due_on.iso8601, days_until: (nubank_recent.due_on - today).to_i,
                     card_bill_id: nubank_recent.id })
      end
    else
      [ marina, rafael ].each do |member|
        Notification.record!(user: member, account: account, kind: "card_overdue",
          subject: cartoes[:nubank], period_key: nubank_recent.billing_month,
          payload: { card: cartoes[:nubank].display_name,
                     amount_cents: nubank_recent.effective_total_cents - nubank_recent.paid_cents,
                     due_on: nubank_recent.due_on.iso8601, card_bill_id: nubank_recent.id })
      end
    end

    # ── Balances LAST: the anchor stamps now, after all history rows, so derived = stored ─
    bank_accounts[:itau].update!(balance_cents: 341_255)
    bank_accounts[:nubank].update!(balance_cents: 214_890)
    bank_accounts[:savings].update!(balance_cents: 520_000)

    # ── Verification ─────────────────────────────────────────────────────────────────────
    brl = lambda do |cents|
      int, frac = cents.abs.divmod(100)
      "#{"-" if cents.negative?}R$ #{int.to_s.reverse.scan(/\d{1,3}/).join(".").reverse},#{format("%02d", frac)}"
    end

    puts "\nSeeded: #{account.bank_accounts.count} bank accounts, #{account.credit_cards.count} cards, " \
         "#{account.incomes.count} incomes, #{account.commitments.count} commitments, " \
         "#{account.transactions.count} transactions, #{past_months.size} full months of history + current."

    suggestions = Budgets::Suggest.call(account)
    names = account.categories.where(id: suggestions.keys).pluck(:id, :name).to_h
    puts "\nBudgets::Suggest (median of the trailing 3 full months):"
    suggestions.sort_by { |id, _| names[id].to_s }.each { |id, cents| puts "  • #{names[id]}: #{brl.(cents)}" }
    abort "FAIL: expected suggestions for ≥4 categories, got #{suggestions.size}." if suggestions.size < 4

    band_events = Budgets::Check.call(account, month: this_month, warn_percent: 80, breach_percent: 100)
    puts "\nBudget bands for #{this_month.strftime('%m/%Y')} (warn 80% / breach 100%):"
    band_events.each do |e|
      puts "  • #{e[:kind]}: #{e[:payload][:category]} — #{brl.(e[:payload][:spent_cents])} de #{brl.(e[:payload][:budget_cents])}"
    end
    kinds = band_events.map { |e| e[:kind] }
    abort "FAIL: expected one budget_warn and one budget_breach, got #{kinds.inspect}." unless
      kinds.include?("budget_warn") && kinds.include?("budget_breach")

    reminders = Reminders::Scan.call(account, from: today, to: today + 3)
    puts "\nReminders::Scan #{today} → #{today + 3}:"
    reminders.each do |e|
      label = e[:payload][:name] || e[:payload][:card]
      puts "  • #{e[:kind]}: #{label} — #{brl.(e[:payload][:amount_cents])} (#{e[:period_key]})"
    end
    abort "FAIL: expected ≥1 reminder event in the next 3 days, got none." if reminders.empty?

    puts "\nCard bills (.plans/credit-cards):"
    account.card_bills.includes(credit_card: :institution).order(:billing_month, :credit_card_id).each do |b|
      puts "  • #{b.credit_card.display_name} #{b.billing_month.strftime('%m/%Y')}: #{brl.(b.effective_total_cents)} — #{b.display_status}"
    end
    carry = CardBills::Carryover.estimate(cartoes[:nubank], recent)
    abort "FAIL: expected carryover + encargos on the Nubank #{recent.strftime('%m/%Y')} bill." unless
      carry && carry[:carryover_cents].positive? && carry[:finance_charges_cents].positive?
    puts "  • carryover onto Nubank #{recent.strftime('%m/%Y')}: #{brl.(carry[:carryover_cents])} + encargos estimados #{brl.(carry[:finance_charges_cents])}"
    abort "FAIL: Itaú divergence must be exactly the edge purchase (#{brl.(edge_cents)})." unless
      itau_recent.reload.computed_total_cents - itau_recent.stated_total_cents == edge_cents
    abort "FAIL: Nubank #{older.strftime('%m/%Y')} must read parcialmente paga." unless nubank_older.reload.status == "partially_paid"
    abort "FAIL: Itaú #{older.strftime('%m/%Y')} must read paga." unless itau_older.reload.status == "paid"
    abort "FAIL: Itaú #{older2.strftime('%m/%Y')} must read parcelada." unless itau_financed.reload.display_status == "financed"
    abort "FAIL: expected the Itaú parcel riding #{recent.strftime('%m/%Y')}." unless
      cartoes[:itau].financing_parcels_cents(recent) == parcel_cents
    puts "  • parcelamento: Itaú #{older2.strftime('%m/%Y')} — entrada #{brl.(down_payment_cents)} + 3 × #{brl.(parcel_cents)}"
    abort "FAIL: expected the pay-CTA notification for both members." unless
      Notification.where(account: account, kind: %w[card_due card_overdue]).count == 2
    # Count-once invariant on the seeded family: sub-card rows ride the ROOT's recent bill.
    sub_recent = account.transactions.posted.kept
                        .where(credit_card_id: subs.values.map(&:id), billing_month: recent).sum(:amount_cents)
    abort "FAIL: expected the sub-cards' rows on the Nubank #{recent.strftime('%m/%Y')} bill." unless sub_recent == 3_490 + 2_500
    abort "FAIL: expected each member to carry a default card." unless
      marina.reload.default_credit_card && rafael.reload.default_credit_card
    puts "  • sub-cards: #{subs.values.map(&:display_name).join(' · ')} (defaults: Marina→Itaú, Rafael→Nubank)"

    s = MonthSummary.new(account, this_month)
    puts "\nMonthSummary #{this_month.strftime('%m/%Y')}: entradas #{brl.(s.incomes_cents)} · " \
         "saídas #{brl.(s.outflows_total_cents)} · guardado #{brl.(s.saved_cents)} · sobra #{brl.(s.remaining_cents)}"

    puts "\nLogins: #{emails[:marina]} / #{password}   ·   #{emails[:rafael]} / #{password}"
  end
end
