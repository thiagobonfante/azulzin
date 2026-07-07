require "test_helper"

class CommitmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst = Institution.find_by(code: "260")
    @account = @user.account.bank_accounts.create!(institution: @inst)
    @card = @user.account.credit_cards.create!(institution: @inst, bill_due_day: 10, closing_offset_days: 7)
  end

  test "index and show render" do
    c = @user.account.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                  amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    get commitments_url
    assert_response :success
    assert_select "form#commitment_form"
    get commitment_url(c)
    assert_response :success
  end

  test "creates a fixed debit commitment" do
    assert_difference -> { @user.account.commitments.count }, 1 do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "pensão", kind: "fixed", amount_reais: "1.000", schedule_day: 5 },
        instrument: "bank_account-#{@account.id}" }
    end
    c = @user.account.commitments.last
    assert_equal "fixed", c.kind
    assert_equal @account, c.bank_account
  end

  test "a card installment creates an unpaid commitment via Installments::Create (no eager posted rows)" do
    assert_no_difference -> { @user.account.transactions.count } do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "celular", kind: "installment", amount_reais: "500", installments_count: 10, installments_paid: 0 },
        instrument: "credit_card-#{@card.id}" }
    end
    c = @user.account.commitments.installment.last
    assert_equal 10, c.installments_count
    assert_equal 500_000, c.total_cents
    assert_equal 0, c.paid_count, "parcels start unpaid and advance as faturas are marked paid"
  end

  test "mid-plan já pagas=13 → installment_no(current)=14, progress 13/36, zero transaction rows" do
    post commitments_url, as: :turbo_stream, params: {
      commitment: { name: "carro", kind: "installment", amount_reais: "1.500", installments_count: 36,
                    installments_paid: 13, schedule_day: 10 },
      instrument: "bank_account-#{@account.id}" }
    c = @user.account.commitments.installment.last
    assert_equal 14, c.installment_no(Date.current.beginning_of_month)
    assert_equal 13, c.paid_count
    assert_equal 0, c.payments.count
  end

  test "destroy soft-deletes unconditionally (payment history preserved, never archived)" do
    c = @user.account.commitments.create!(bank_account: @account, name: "x", kind: "fixed", amount_cents: 100, schedule_day: 5, starts_on: Date.current)
    delete commitment_url(c)
    assert c.reload.soft_deleted?
    assert_not @user.account.commitments.kept.exists?(c.id)

    # With payments the old code archived instead of destroying; now it soft-deletes and the
    # posted payment stays in the ledger. archived_at is untouched (a separate business state).
    c2 = @user.account.commitments.create!(bank_account: @account, name: "y", kind: "fixed", amount_cents: 100, schedule_day: 5, starts_on: Date.current)
    Commitments::MarkPaid.call(c2, Date.current.beginning_of_month)
    delete commitment_url(c2)
    assert c2.reload.soft_deleted?
    assert_not c2.archived?
    assert_equal 1, c2.payments.posted.kept.count, "the payment survives in the ledger"
  end

  test "a subscription created after its charge day starts next month (no retroactive vencimento)" do
    travel_to Date.new(2026, 7, 6) do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "iCloud", kind: "subscription", amount_reais: "29,90", schedule_day: 1 },
        instrument: "credit_card-#{@card.id}" }
      c = @user.account.commitments.subscription.last
      assert_equal Date.new(2026, 8, 1), c.starts_on
      assert_equal Date.new(2026, 8, 1), c.next_charge_month
    end
  end

  test "a commitment created before its charge day keeps the current month" do
    travel_to Date.new(2026, 7, 6) do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "aluguel", kind: "fixed", amount_reais: "1.000", schedule_day: 15 },
        instrument: "bank_account-#{@account.id}" }
      c = @user.account.commitments.last
      assert_equal Date.new(2026, 7, 1), c.starts_on
      assert_equal Date.new(2026, 7, 1), c.next_charge_month
    end
  end

  test "an adopted posted charge rewinds starts_on so the elapsed month shows as paid" do
    travel_to Date.new(2026, 7, 6) do
      card = @user.account.credit_cards.create!(institution: @inst, bill_due_day: 28, closing_offset_days: 7)
      month = card.billing_month_for(Date.current)   # bill still open → July
      charge = @user.account.transactions.create!(credit_card: card, direction: "expense", status: "posted",
                                          amount_cents: 2_990, occurred_on: Date.new(2026, 7, 1), merchant: "iCloud",
                                          billing_month: month, billing_month_manual: true)
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "iCloud", kind: "subscription", amount_reais: "29,90", schedule_day: 1 },
        instrument: "credit_card-#{card.id}" }
      c = @user.account.commitments.subscription.last
      assert_equal c.id, charge.reload.commitment_id
      assert_equal Date.new(2026, 7, 1), c.starts_on
      assert c.paid_in?(Date.new(2026, 7, 1))
      assert_equal Date.new(2026, 8, 1), c.next_charge_month
    end
  end

  test "bill-constancy: a card subscription retroactively links its charge; the bill stays constant" do
    month  = @card.billing_month_for(Date.current)
    charge = @user.account.transactions.create!(credit_card: @card, direction: "expense", status: "posted",
                                        amount_cents: 5_590, occurred_on: Date.current, merchant: "Netflix",
                                        billing_month: month, billing_month_manual: true)
    before = @card.bill_cents(month)
    post commitments_url, as: :turbo_stream, params: {
      commitment: { name: "Netflix", kind: "subscription", amount_reais: "55,90" },
      instrument: "credit_card-#{@card.id}" }
    c = @user.account.commitments.subscription.last
    assert_equal c.id, charge.reload.commitment_id      # linked at creation (pass 2)
    assert_equal before, @card.bill_cents(month)        # projection swapped for the posted row
  end

  test "show renders the pending list and paid accordion for each kind" do
    inst = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                     amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                     schedule_day: 10, starts_on: Date.current.beginning_of_month)
    Commitments::MarkPaid.call(inst, Date.current.beginning_of_month)
    get commitment_url(inst)
    assert_response :success
    assert_select "#commitment_occurrences details"    # paid accordion

    sub = @user.account.commitments.create!(credit_card: @card, name: "Netflix", kind: "subscription",
                                    amount_cents: 5_590, starts_on: Date.current.beginning_of_month << 3)
    get commitment_url(sub)
    assert_response :success
  end

  test "pay_batch pays the selected parcels splitting the typed total" do
    month = Date.current.beginning_of_month
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                  schedule_day: 10, starts_on: month)
    months = [ month, month >> 1, month >> 2 ].map { |m| m.strftime("%Y-%m") }
    assert_difference -> { @user.account.transactions.posted.count }, 3 do
      patch pay_batch_commitment_url(c), params: { months: months, amount_reais: "3.400,00" }
    end
    assert_redirected_to commitment_url(c)
    assert_equal 340_000, c.payments.posted.sum(:amount_cents)   # split covers the exact total
    assert [ month, month >> 1, month >> 2 ].all? { |m| c.paid_in?(m) }
  end

  test "pay_batch skips already-paid months and rejects blank input" do
    month = Date.current.beginning_of_month
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                  schedule_day: 10, starts_on: month)
    Commitments::MarkPaid.call(c, month)
    assert_difference -> { @user.account.transactions.posted.count }, 1 do
      patch pay_batch_commitment_url(c), params: { months: [ month, month >> 1 ].map { |m| m.strftime("%Y-%m") },
                                                   amount_reais: "1.100,00" }
    end
    assert_equal 110_000, c.payments.posted.find_by(billing_month: month >> 1).amount_cents

    patch pay_batch_commitment_url(c), params: { months: [], amount_reais: "100,00" }
    assert_redirected_to commitment_url(c)
    assert flash[:alert].present?
  end

  test "settle posts the payoff amount and archives the plan" do
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                  schedule_day: 10, starts_on: Date.current.beginning_of_month)
    assert_difference -> { @user.account.transactions.posted.count }, 1 do
      patch settle_commitment_url(c), params: { amount_reais: "27.600,00" }
    end
    assert_redirected_to commitments_url
    assert c.reload.archived?
    assert_equal 2_760_000, c.payments.posted.last.amount_cents
  end

  test "settle rejects non-installment and card commitments" do
    fixed = @user.account.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                      amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    patch settle_commitment_url(fixed), params: { amount_reais: "100,00" }
    assert_redirected_to commitment_url(fixed)
    assert_not fixed.reload.archived?
  end

  # ── Editing installments_count: grow/shrink the plan, never below what's already paid ──

  test "update grows a debit installment plan: count and total follow" do
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                  schedule_day: 10, starts_on: Date.current.beginning_of_month)
    patch commitment_url(c), params: { commitment: { name: "carro", installments_count: 38 } }
    assert_redirected_to commitment_url(c)
    c.reload
    assert_equal 38, c.installments_count
    assert_equal 120_000 * 38, c.total_cents
  end

  test "update can't shrink a debit plan below paid parcels; shrinking to exactly them ends it" do
    month = Date.current.beginning_of_month
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 10, total_cents: 1_200_000,
                                  schedule_day: 10, starts_on: month)
    Commitments::MarkPaid.call(c, month)
    Commitments::MarkPaid.call(c, month >> 1)

    patch commitment_url(c), params: { commitment: { name: "carro", installments_count: 1 } }
    assert_response :unprocessable_entity
    assert_equal 10, c.reload.installments_count

    patch commitment_url(c), params: { commitment: { name: "carro", installments_count: 2 } }
    assert_redirected_to commitment_url(c)
    c.reload
    assert_equal 2, c.installments_count
    assert_nil c.next_charge_month, "plan shrunk to its paid parcels has nothing left to charge"
  end

  test "update respects presumed-paid parcels from mid-plan onboarding" do
    c = @user.account.commitments.create!(bank_account: @account, name: "carro", kind: "installment",
                                  amount_cents: 120_000, installments_count: 36, total_cents: 4_320_000,
                                  schedule_day: 10, starts_on: Date.current.beginning_of_month << 5)
    assert_equal 5, c.min_installments_count
    patch commitment_url(c), params: { commitment: { name: "carro", installments_count: 4 } }
    assert_response :unprocessable_entity
    assert_equal 36, c.reload.installments_count
  end

  test "update grows a card installment: count and total follow (parcels stay computed)" do
    c = Installments::Create.call(account: @user.account, created_by: @user, card: @card,
                                  total_cents: 500_000, count: 10, occurred_on: Date.current, merchant: "celular")
    patch commitment_url(c), params: { commitment: { name: "celular", installments_count: 12 } }
    assert_redirected_to commitment_url(c)
    c.reload
    assert_equal 12, c.installments_count
    assert_equal 600_000, c.total_cents
    assert_equal 0, c.payments.count, "no eager parcel rows are created on resize"
  end

  test "update shrinks a card installment: count and total follow" do
    c = Installments::Create.call(account: @user.account, created_by: @user, card: @card,
                                  total_cents: 500_000, count: 10, occurred_on: Date.current, merchant: "celular")
    patch commitment_url(c), params: { commitment: { name: "celular", installments_count: 8 } }
    assert_redirected_to commitment_url(c)
    c.reload
    assert_equal 8, c.installments_count
    assert_equal 400_000, c.total_cents
  end

  test "update can't drop card parcels already marked paid on closed bills" do
    c = Installments::Create.call(account: @user.account, created_by: @user, card: @card,
                                  total_cents: 500_000, count: 10, occurred_on: Date.current << 4, merchant: "celular")
    # Mark the first three parcels paid ("Ajustar"): they land on already-closed bills.
    [ c.starts_on, c.starts_on >> 1, c.starts_on >> 2 ].each { |m| Commitments::MarkPaid.call(c, m, amount: c.amount_cents) }
    closed = c.payments.posted.kept.where(billing_month: ...@card.current_open_bill_month).count
    assert_operator closed, :>=, 3
    patch commitment_url(c), params: { commitment: { name: "celular", installments_count: 2 } }
    assert_response :unprocessable_entity
    assert_equal 10, c.reload.installments_count
  end

  test "update leaves the count alone for non-installment kinds" do
    fixed = @user.account.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                      amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    patch commitment_url(fixed), params: { commitment: { name: "aluguel novo", installments_count: 12 } }
    assert_redirected_to commitment_url(fixed)
    assert_nil fixed.reload.installments_count
    assert_equal "aluguel novo", fixed.name
  end

  # ── No instruments (onboarding skipped): creation is blocked until an account/card exists ──

  def remove_instruments
    @account.soft_delete!(by: @user)
    @card.soft_delete!(by: @user)
  end

  test "index with no instruments shows the create-an-account-first prompt instead of the form" do
    remove_instruments
    get commitments_url
    assert_response :success
    assert_includes response.body, I18n.t("shared.needs_instrument.title", locale: :"pt-BR")
    assert_select "form#commitment_form", false
  end

  test "create with no instruments is blocked" do
    remove_instruments
    assert_no_difference -> { @user.account.commitments.count } do
      post commitments_url, params: {
        commitment: { name: "pensão", kind: "fixed", amount_reais: "1.000", schedule_day: 5 },
        instrument: "" }
    end
    assert_redirected_to commitments_url
  end
end
