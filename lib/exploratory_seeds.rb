# Numbered, re-runnable dev seeds for MANUAL exploratory testing with bin/dev-fake.
# Each scenario N wipes + recreates test-N@azulzin.dev (and test-Nb@… when a partner exists)
# with a calibrated data shape, reusing the E2E::Scenario packs so manual testing exercises
# the exact same frozen cents the automated suite pins. Walkthroughs: docs/exploratory-tests.md.
#
#   bin/rails exploratory:list
#   bin/rails "exploratory:seed[4]"
#   bin/rails exploratory:seed_all
#   bin/rails "exploratory:wipe[4]"
module ExploratorySeeds
  PASSWORD = "test1234"

  def self.email(n, suffix = nil)  = "test-#{n}#{suffix}@azulzin.dev"
  def self.phone(n)                = format("5511%09d", 910_000_000 + n)   # owner
  def self.partner_phone(n)        = format("5511%09d", 920_000_000 + n)

  # ── registry ─────────────────────────────────────────────────────────────────────────────
  # Each entry: what the account contains, which docs/exploratory-tests.md section uses it.
  SCENARIOS = {
    1  => { slug: "wa-capture",      title: "Captura WhatsApp (texto/áudio/imagem/PDF)" },
    2  => { slug: "wa-verification", title: "Verificação de telefone WhatsApp (código AZUL-)" },
    3  => { slug: "couple",          title: "Casal — dois telefones, um ledger" },
    4  => { slug: "budgets-history", title: "Orçamentos calibrados + histórico p/ backfill" },
    5  => { slug: "reminders",       title: "Lembretes de contas (vencendo/atrasada/fatura)" },
    6  => { slug: "goal-on-track",   title: "Meta ativa em dia (no ritmo)" },
    7  => { slug: "goal-at-risk",    title: "Meta ativa em risco (~93% do esperado)" },
    8  => { slug: "goal-off-track",  title: "Meta ativa fora do ritmo (50%)" },
    9  => { slug: "goal-cuts",       title: "Meta com cortes de orçamento (cap < orçamento)" },
    10 => { slug: "goal-chat",       title: "Pronto p/ criar meta (chat WA + web, sem meta)" },
    11 => { slug: "imports",         title: "Importação de extrato/fatura" },
    12 => { slug: "onboarding",      title: "Usuário confirmado, wizard incompleto" },
    13 => { slug: "invites",         title: "Convites/multi-usuário (+ convidado test-13b)" },
    14 => { slug: "tenancy-leak",    title: "Conta-canário p/ vazamento entre contas (R$ 666,66)" },
    15 => { slug: "goal-celebrate",  title: "Meta a R$ 50,00 do alvo (festa 🎉)" }
  }.freeze

  def self.run(n)
    n = Integer(n)
    entry = SCENARIOS.fetch(n) { abort "Unknown scenario #{n}. Run: bin/rails exploratory:list" }
    prepare!
    wipe(n)
    scenario, notes = send(entry[:slug].tr("-", "_"), n)
    pin!(scenario, n, entry[:title]) if scenario
    announce(n, entry, scenario, notes)
    scenario
  end

  def self.wipe(n)
    # DemoSeed-style: account first (tenant cascade), then each pinned User row.
    [ email(n), email(n, "b") ].each do |mail|
      next unless (existing = User.find_by(email_address: mail))
      puts "  wiping #{mail} (user ##{existing.id})…"
      existing.account&.destroy!
      existing.destroy!
    end
  end

  def self.prepare!
    unless defined?(E2E::Seq)
      # scenario.rb's only non-app dependency; helpers.rb (its home) pulls capybara → dev LoadError.
      seq = Module.new do
        @n = 0
        @mutex = Mutex.new
        def self.next = @mutex.synchronize { @n += 1 }
      end
      e2e = defined?(::E2E) ? ::E2E : Object.const_set(:E2E, Module.new)
      e2e.const_set(:Seq, seq)
    end
    require Rails.root.join("test/test_helpers/e2e/scenario").to_s
    Institution.load_registry!
  end

  # After the pack builds with throwaway e2e-N identities, pin the memorable ones.
  # Phone changes must re-run verify_whatsapp! so whatsapp_id/jid follow the new number.
  def self.pin!(scenario, n, title)
    repin_user(scenario.owner, email(n), phone(n), "Teste #{n}")
    if (partner = scenario.partner)
      repin_user(partner, email(n, "b"), partner_phone(n), "Teste #{n}B")
    end
    scenario.account.update!(name: "Teste #{n} — #{title}")
  end

  def self.repin_user(user, mail, fone, name)
    user.update!(email_address: mail, password: PASSWORD, name: name, phone: fone)
    user.verify_whatsapp!("#{fone}@c.us") if user.phone_verified_at?
  end

  def self.announce(n, entry, scenario, notes)
    puts "\n✔ Cenário #{n} — #{entry[:title]}"
    puts "  login:  #{email(n)} / #{PASSWORD}"
    if scenario
      scenario.members.each do |u|
        wa = u.phone_verified_at? ? "JID #{u.whatsapp_jid} (verificado)" : "telefone #{u.phone} (NÃO verificado)"
        puts "  #{u.email_address}: #{wa}"
      end
    end
    Array(notes).each { |line| puts "  #{line}" }
    puts "  passos: docs/exploratory-tests.md → seed #{n}"
  end

  # ── builders (return [scenario_or_nil, notes]) ───────────────────────────────────────────

  def self.wa_capture(n)
    scenario = E2E::Scenario.build(:solo_basic).add_caixinha!.wa_verified!
    # Merchant memory needs same-merchant user-categorized history (Categories::Suggest).
    [ 21, 14, 7 ].each do |days_ago|
      scenario.expense(merchant: "iFood", category: "Restaurantes", instrument: scenario.itau,
                       cents: 4_590, on: Date.current - days_ago)
    end
    [ scenario, [ "memória de categoria pronta: iFood → Restaurantes (3 lançamentos seus)" ] ]
  end

  def self.wa_verification(n)
    scenario = E2E::Scenario.build(:solo_basic)   # phone set by pin!, deliberately NOT verified
    code = scenario.owner.whatsapp_verification_code!(force: true)
    [ scenario, [ "código de verificação: #{code} (envie do número #{phone(n)} no simulador :3001)" ] ]
  end

  def self.couple(n)
    [ E2E::Scenario.build(:couple).add_caixinha!, [] ]
  end

  def self.budgets_history(n)
    scenario = E2E::Scenario.build(:history_calibrated).wa_verified!
    # Backfill material: uncategorized posted rows — 2 hit merchant memory ("Supermercado E2E"
    # has user-categorized history), 4 need the closed-set LLM pass.
    [ [ "Supermercado E2E", 6_780 ], [ "Supermercado E2E", 12_340 ],
      [ "Pet Shop Miau", 8_990 ], [ "Pet Shop Miau", 15_000 ],
      [ "Farmacia Preco Bom", 3_450 ], [ "Uber Trip", 2_290 ] ].each_with_index do |(merchant, cents), i|
      scenario.account.transactions.create!(
        merchant: merchant, direction: "expense", status: "posted", source: "manual",
        amount_cents: cents, occurred_on: Date.current.beginning_of_month << (1 + i % 2),
        confirmed_at: Time.current, bank_account: scenario.itau, created_by: scenario.owner)
    end
    [ scenario, [ "bandas: Mercado 88,3% WARN · Restaurantes 108% BREACH · Transporte 80% exato · Lazer 79,997% silencioso",
                  "6 lançamentos SEM categoria nos meses passados (material do backfill)" ] ]
  end

  def self.reminders(n)
    scenario = E2E::Scenario.build(:reminders_due).wa_verified!
    [ scenario, [ "Condomínio vence amanhã · Luz atrasada 2d (na carência) · Água atrasada 5d (fora) · fatura fecha amanhã · Freela amanhã" ] ]
  end

  def self.goal_on_track(n)  = goal_pack(paid: [ 1, 1, 1 ])
  def self.goal_off_track(n) = goal_pack(paid: [ 1, 0.5, 0 ])

  # The pack's [1,1,0.8] (2.8× monthly saved) only drops below the 95% band edge in the last
  # days of the month (expected ramps 2×→3× monthly via the MTD pro-rata). Trim the newest
  # contributions so guardado reads exactly 93% of TODAY's expected — at_risk on any run day.
  def self.goal_at_risk(n)
    scenario = E2E::Scenario.build(:goal_active, paid: [ 1, 1, 0.8 ]).wa_verified!
    goal = scenario.goal
    progress = Goals::Progress.new(goal)
    delta = progress.actual_cents - (progress.expected_cents * 93 / 100)
    goal.account.transactions.guardado_into(goal.savings_account_ids)
        .order(occurred_on: :desc, id: :desc).each do |t|
      break if delta <= 0
      cut = [ delta, t.amount_cents ].min
      cut == t.amount_cents ? t.destroy! : t.update!(amount_cents: t.amount_cents - cut)
      delta -= cut
    end
    [ scenario, [ "meta 'Carro' ativa há 2 meses, guardado ajustado p/ 93% do esperado de HOJE (banda 81–95%)",
                  "⚠ o esperado cresce a cada dia — re-rode o seed no DIA do teste" ] ]
  end

  def self.goal_pack(paid:)
    warn_early_month!
    scenario = E2E::Scenario.build(:goal_active, paid: paid).wa_verified!
    [ scenario, [ "meta 'Carro' ativa há 2 meses, parcelas pagas: #{paid.inspect}" ] ]
  end

  def self.goal_cuts(n)
    scenario = E2E::Scenario.build(:goal_cuts).wa_verified!
    [ scenario, [ "cap da meta R$ 400,00 < orçamento R$ 600,00; gasto atual R$ 340,00 → warn contra o cap" ] ]
  end

  def self.goal_chat(n)
    scenario = E2E::Scenario.build(:solo_basic).add_caixinha!.wa_verified!
    scenario.ensure_income_history!   # Analyzer baseline the goal plans need
    [ scenario, [ "sem meta ativa; caixinha + 3 meses de salário recebido (baseline do Analyzer)" ] ]
  end

  def self.imports(n)
    [ E2E::Scenario.build(:solo_basic).add_caixinha!, [ "Itaú + cartão Nubank prontos p/ casar propostas de extrato/fatura" ] ]
  end

  def self.onboarding(n)
    # Mid-signup state: confirmed, bootstrapped, but the wizard never ran (no onboard!).
    user = User.create!(email_address: email(n), password: PASSWORD, name: "Teste #{n}",
                        phone: phone(n), confirmed_at: Time.current)
    Accounts::Bootstrap.call(user)
    [ nil, [ "usuário confirmado SEM onboarding — qualquer URL do app devolve ao wizard" ] ]
  end

  def self.invites(n)
    owner = E2E::Scenario.build(:solo_basic)
    invitee = E2E::Scenario.build(:solo_basic)
    invitee.expense(merchant: "Livraria do Convidado", category: "Outros",
                    instrument: invitee.itau, cents: 9_900, on: Date.current)
    repin_user(invitee.owner, email(n, "b"), partner_phone(n), "Teste #{n}B")
    invitee.account.update!(name: "Solo do Convidado #{n}b")
    [ owner, [ "convidado test-#{n}b@azulzin.dev tem conta própria COM dados (recusa de convite MU-02)" ] ]
  end

  def self.tenancy_leak(n)
    scenario = E2E::Scenario.build(:solo_basic)
    scenario.expense(merchant: "VAZAMENTO LTDA", category: "Outros",
                     instrument: scenario.itau, cents: 66_666, on: Date.current)
    [ scenario, [ "canário: R$ 666,66 'VAZAMENTO LTDA' — não pode aparecer em NENHUMA outra conta/export" ] ]
  end

  def self.goal_celebrate(n)
    warn_early_month!
    scenario = E2E::Scenario.build(:goal_active, paid: [ 1, 1, 1 ]).wa_verified!
    goal = scenario.goal
    saved = 3 * goal.monthly_target_cents
    goal.update!(target_cents: saved + 5_000)   # one R$ 50,00 contribution crosses the line
    [ scenario, [ "faltam exatos R$ 50,00 p/ o alvo — um aporte de R$ 50 dispara a festa 🎉" ] ]
  end

  def self.warn_early_month!
    return if Date.current.day > 5
    puts "  ⚠ dia #{Date.current.day} ≤ 5: o pagamento do salário (dia 5) ainda não passou — " \
         "as bandas de risco da meta podem ler diferente do documentado (rode do dia 6 ao 25)."
  end
end
