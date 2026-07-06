# Seeds the dev database with the contents of tmp/controle_gastos.xlsx (Jul/2026 – Jul/2027),
# the personal spreadsheet azulzin replaces, so every app figure can be checked line-by-line
# against the sheet. The data below is an embedded snapshot of the sheet (as of 2026-07-06),
# not parsed from the file — values are integer cents, exactly as typed in the sheet.
#
# Only DEFINITIONS and ACTUALS are seeded. Everything the sheet derives by formula (the
# monthly projections from Set/26 onward, running balances, faturas) is deliberately NOT
# seeded — the app must derive it from the same inputs. The task ends by comparing the
# app's MonthSummary against the sheet's RESUMO panel for Jul/Ago/Set 2026.
#
# Assumptions where the sheet is silent:
#   • incomes land on day 5; fixed debits are due on day 10 (the sheet's day columns are blank)
#   • cards: due day 10, closing 7 days before (the sheet tracks bills by month only), so the
#     card purchases typed on the Ago/26 sheet are dated 2026-07-04 and land on the Ago fatura
#   • Jul/26 rows identical to Config are projections (left unpaid); typed rows are posted
#     actuals. "Carro (emprestimo)" was posted at the sheet's overridden 3.090,02 (parcela 1/17)
#
# Usage: bin/rails dev:seed_spreadsheet [EMAIL=planilha@azulzin.dev] [PASSWORD=planilha123]
namespace :dev do
  desc "Seed dev data from the tmp/controle_gastos.xlsx snapshot (wipes + recreates the seed user)"
  task seed_spreadsheet: :environment do
    abort "dev:seed_spreadsheet only runs in development." unless Rails.env.development?

    email    = ENV.fetch("EMAIL", "planilha@azulzin.dev")
    password = ENV.fetch("PASSWORD", "planilha123")
    jul      = Date.new(2026, 7, 1)
    ago      = Date.new(2026, 8, 1)

    if (existing = User.find_by(email_address: email))
      puts "Wiping #{email} (user ##{existing.id}) and all its financial data…"
      existing.account&.destroy!   # the LGPD cascade lives on Account now (spine D8)
      existing.destroy!
    end

    Institution.load_registry!
    inst = {
      santander: Institution.find_by!(code: "033"),
      nubank:    Institution.find_by!(code: "260"),
      bb:        Institution.find_by!(code: "001")
    }

    user = User.create!(email_address: email, password: password, name: "Thiago", confirmed_at: Time.current)
    # A seed user isn't created through a signup controller, so mint its account here (spine D1).
    account = Accounts::Bootstrap.call(user)
    user.reload            # refresh the has_one :account association before onboard!
    user.onboard!          # default categories (into the account) + skip the wizard

    # ── Config: SALDOS DE ABERTURA (início de Julho/2026) ────────────────────────────────
    accounts = {
      santander:     account.bank_accounts.create!(institution: inst[:santander], balance_cents: 105_386),
      nubank_thiago: account.bank_accounts.create!(institution: inst[:nubank], nickname: "Nubank (Thiago)", balance_cents: 357_625),
      nubank_fran:   account.bank_accounts.create!(institution: inst[:nubank], nickname: "Nubank (Fran)", balance_cents: 0),
      bb:            account.bank_accounts.create!(institution: inst[:bb], balance_cents: 0)
    }

    # The sheet tracks two faturas (Santander / Nubank) with no cycle info; due day 10 +
    # default closing offset 7 puts purchases from Jul/04 onward on the Ago/26 bill.
    cards = {
      santander: account.credit_cards.create!(institution: inst[:santander], bill_due_day: 10),
      nubank:    account.credit_cards.create!(institution: inst[:nubank], bill_due_day: 10)
    }

    # ── Config: ENTRADAS FIXAS ───────────────────────────────────────────────────────────
    incomes = {
      "Salário Thiago" => account.incomes.create!(name: "Salário Thiago", bank_account: accounts[:santander],     amount_cents: 4_802_580, schedule_day: 5),
      "Salário Fran"   => account.incomes.create!(name: "Salário Fran",   bank_account: accounts[:nubank_fran],   amount_cents:   460_080, schedule_day: 5),
      "Pensão"         => account.incomes.create!(name: "Pensão",         bank_account: accounts[:bb],            amount_cents:   234_187, schedule_day: 5)
    }

    # ── Config: DESPESAS FIXAS (tipo "Fixa" — pagas pelas contas) ────────────────────────
    [
      [ "Financiamento da casa", :santander,     501_216 ],
      [ "Telefone",              :nubank_thiago,  32_608 ],
      [ "Lanche Dudu",           :nubank_fran,    18_000 ],
      [ "Pensão Vith",           :nubank_fran,   120_000 ],
      [ "Personal Dudu",         :nubank_fran,    36_000 ],
      [ "Academia Dudu",         :nubank_fran,    11_900 ],
      [ "Consórcio",             :santander,     171_025 ],
      [ "Unimed",                :santander,     143_594 ],
      [ "Água e Esgoto",         :santander,      17_184 ],
      [ "Internet Vith",         :santander,      10_214 ],
      [ "Aluguel Vith",          :santander,     260_000 ],
      [ "Faculdade Vith",        :santander,     105_753 ],
      [ "Psicologo Thiago",      :santander,      80_000 ],
      [ "Seguro Casa",           :santander,      32_853 ],
      [ "Seguro Vida",           :santander,      17_132 ],
      [ "Seguro Casa Vith",      :santander,       2_084 ],
      [ "Boleto Cooper Dudu",    :nubank_fran,     8_000 ]
    ].each do |name, acct_key, cents|
      account.commitments.create!(kind: "fixed", name: name, bank_account: accounts[acct_key],
                               amount_cents: cents, starts_on: jul, schedule_day: 10)
    end

    # ── Config: DESPESAS FIXAS (tipo "Parcelada" — início Jul/26) ────────────────────────
    carro_parcelado = account.commitments.create!(
      kind: "installment", name: "Carro (parcelado)", bank_account: accounts[:nubank_fran],
      amount_cents: 250_257, starts_on: jul, installments_count: 11, total_cents: 2_752_827)
    carro_emprestimo = account.commitments.create!(
      kind: "installment", name: "Carro (emprestimo)", bank_account: accounts[:nubank_thiago],
      amount_cents: 318_330, starts_on: jul, installments_count: 17, total_cents: 5_411_610)

    # ── PARCELAMENTOS do cartão (todos Santander, início Ago/26) ─────────────────────────
    [
      [ "Perfume",                 7_235, 9,    65_115 ],
      [ "Farmacia",               19_440, 1,    19_440 ],
      [ "Amazon",                 10_340, 2,    20_680 ],
      [ "Raquel (Cabelo)",        50_460, 1,    50_460 ],
      [ "Farmacia",                6_945, 5,    34_725 ],
      [ "Insider",                36_678, 1,    36_678 ],
      [ "Farmacia",               46_567, 3,   139_701 ],
      [ "Mercado Livre",           5_584, 5,    27_920 ],
      [ "Celular Dudu",           56_900, 8,   455_200 ],
      [ "Riachuelo",               8_001, 1,     8_001 ],
      [ "Centauro",               21_256, 6,   127_536 ],
      [ "Airbnb",                  6_775, 4,    27_100 ],
      [ "Farmacia",                9_666, 3,    28_998 ],
      [ "Farmacia",               38_396, 3,   115_188 ],
      [ "Mercado Livre",           5_586, 4,    22_344 ],
      [ "Farmacia",               43_460, 2,    86_920 ],
      [ "Netshoes",                8_999, 3,    26_997 ],
      [ "Amazon (Judite)",        25_305, 3,    75_915 ],
      [ "Britania (Lava louças)", 25_641, 2,    51_282 ],
      [ "Dentista (Thiago)",      29_000, 3,    87_000 ]
    ].each do |name, cents, count, total|
      account.commitments.create!(kind: "installment", name: name, credit_card: cards[:santander],
                               amount_cents: cents, starts_on: ago, installments_count: count, total_cents: total)
    end

    # ── ASSINATURAS do cartão (início Ago/26; sem dia ⇒ fim do mês) ──────────────────────
    [
      [ "Amazon Prime",        :nubank,      1_990 ],
      [ "Awesome Screenshot",  :nubank,      4_454 ],
      [ "ChatGPT",             :nubank,     11_074 ],
      [ "Nu Seguro Vida",      :nubank,      2_477 ],
      [ "Fireflies (Fran)",    :nubank,     15_866 ],
      [ "Seguro carro",        :nubank,     25_804 ],
      [ "Google One (Fran)",   :nubank,      1_499 ],
      [ "Ampernet",            :nubank,     15_990 ],
      [ "ChatGPT",             :nubank,     11_144 ],
      [ "Youtube Premium",     :nubank,      5_390 ],
      [ "Netflix",             :nubank,      4_490 ],
      [ "One Drive (Fran)",    :nubank,        600 ],
      [ "Easyhooks (Google)",  :nubank,      4_900 ],
      [ "Coopermundi",         :santander, 104_700 ]
    ].each do |name, card, cents|
      account.commitments.create!(kind: "subscription", name: name, credit_card: cards[card],
                               amount_cents: cents, starts_on: ago)
    end

    # ── Jul/26 actuals: entradas recebidas + parcela do carro paga (valor da planilha) ───
    incomes.each_value { |income| Incomes::MarkReceived.call(income, jul) }
    Commitments::MarkPaid.call(carro_emprestimo, jul, amount: 309_002)

    # ── Jul/26 actuals: saídas avulsas digitadas na planilha ─────────────────────────────
    [
      [ "Fatura Nubank (Thiago)",         :nubank_thiago,   227_707 ],
      [ "Fatura Santander",               :santander,     2_170_636 ],
      [ "Fatura Nubank (Frank)",          :nubank_fran,     172_054 ],
      [ "Luz Vitoria",                    :santander,         4_101 ],
      [ "Iof e taxas",                    :santander,            53 ],
      [ "Parcela adiantada carro (emp)",  :nubank_thiago,   194_061 ],
      [ "Farmacia",                       :nubank_fran,       4_000 ],
      [ "Presente Vith",                  :santander,        25_000 ],
      [ "Rematricula Vith",               :santander,       123_147 ],
      [ "Mercado",                        :nubank_fran,       2_056 ]
    ].each do |merchant, acct_key, cents|
      account.transactions.create!(merchant: merchant, direction: "expense", status: "posted",
                                confirmed_at: Time.current, source: "manual", amount_cents: cents,
                                occurred_on: Date.new(2026, 7, 5), bank_account: accounts[acct_key])
    end

    # ── Jul/26 actuals: transferências entre contas ──────────────────────────────────────
    [
      [ "Transf. pensão",       :bb,        :nubank_fran,     234_187 ],
      [ "Transf. entre bancos", :santander, :nubank_thiago, 1_000_000 ],
      [ "Transf. para Fran",    :santander, :nubank_fran,     100_000 ]
    ].each do |merchant, from, to, cents|
      account.transactions.create!(merchant: merchant, direction: "transfer", status: "posted",
                                confirmed_at: Time.current, source: "manual", amount_cents: cents,
                                occurred_on: Date.new(2026, 7, 5),
                                bank_account: accounts[from], transfer_to_bank_account: accounts[to])
    end

    # ── CARTÃO — COMPRAS typed on the Ago/26 sheet: purchases already made, dated after
    #    the Jul closing (Jul/03) so they land on the Ago/26 fatura like in the sheet ─────
    [
      [ "Aiqfome",             :nubank,    44_556 ],
      [ "Mercado",             :nubank,     5_100 ],
      [ "Restaurante",         :nubank,    14_988 ],
      [ "Farmacia",            :nubank,    30_714 ],
      [ "Gasolina",            :nubank,    16_927 ],
      [ "Registro.br",         :nubank,     4_000 ],
      [ "Presente amiga Dudu", :nubank,    18_500 ],
      [ "Aiqfome",             :santander, 13_197 ],
      [ "Chofer",              :santander,  2_543 ],
      [ "Farmacia",            :santander, 19_819 ],
      [ "Lidia café",          :santander, 16_220 ],
      [ "Panificadora",        :santander,    629 ]
    ].each do |merchant, card, cents|
      account.transactions.create!(merchant: merchant, direction: "expense", status: "posted",
                                confirmed_at: Time.current, source: "manual", amount_cents: cents,
                                occurred_on: Date.new(2026, 7, 4), credit_card: cards[card])
    end

    # ── Verify the app derives the sheet's RESUMO figures ────────────────────────────────
    brl = lambda do |cents|
      int, frac = cents.abs.divmod(100)
      "#{"-" if cents.negative?}R$ #{int.to_s.reverse.scan(/\d{1,3}/).join(".").reverse},#{format("%02d", frac)}"
    end

    jul_s = MonthSummary.new(account, jul)
    ago_s = MonthSummary.new(account, ago)
    set_s = MonthSummary.new(account, Date.new(2026, 9, 1))
    checks = [
      [ "Jul/26 Total de Entradas",        5_496_847, jul_s.entradas_cents ],
      [ "Jul/26 Total de Saídas em Conta", 5_049_637, jul_s.saidas_cents ],
      [ "Jul/26 Gasto em Cartões",                 0, jul_s.faturas_cents ],
      [ "Jul/26 Sobra do Mês",               447_210, jul_s.remaining_cents ],
      [ "Ago/26 Total de Entradas",        5_496_847, ago_s.entradas_cents ],
      [ "Ago/26 Total de Saídas em Conta", 2_136_150, ago_s.saidas_cents ],
      [ "Ago/26 Fatura Santander",           619_342, ago_s.bill_totals[cards[:santander]] ],
      [ "Ago/26 Fatura Nubank",              240_463, ago_s.bill_totals[cards[:nubank]] ],
      [ "Ago/26 Sobra do Mês",             2_500_892, ago_s.remaining_cents ],
      [ "Set/26 Gasto em Cartões",           558_033, set_s.faturas_cents ],
      [ "Set/26 Sobra do Mês",             2_802_664, set_s.remaining_cents ]
    ]

    puts "\nSeeded: #{account.bank_accounts.count} accounts, #{account.credit_cards.count} cards, " \
         "#{account.incomes.count} incomes, #{account.commitments.count} commitments, " \
         "#{account.transactions.count} transactions."
    puts "\nSpreadsheet alignment (sheet RESUMO vs app MonthSummary):"
    failures = checks.reject { |_, expected, actual| expected == actual }
    checks.each do |label, expected, actual|
      mark = expected == actual ? "✓" : "✗"
      diff = expected == actual ? "" : "  (sheet: #{brl.(expected)})"
      puts "  #{mark} #{label}: #{brl.(actual)}#{diff}"
    end
    puts failures.empty? ? "\nAll checkpoints match the spreadsheet." : "\n#{failures.size} checkpoint(s) DIVERGE from the spreadsheet."

    puts "\nLogin: #{email} / #{password}"
  end
end
