require "test_helper"

class CommitmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst = Institution.find_by(code: "260")
    @account = @user.bank_accounts.create!(institution: @inst)
    @card = @user.credit_cards.create!(institution: @inst, bill_due_day: 10, closing_offset_days: 7)
  end

  test "index and show render" do
    c = @user.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                  amount_cents: 100_000, schedule_day: 5, starts_on: Date.current)
    get commitments_url
    assert_response :success
    assert_select "form#commitment_form"
    get commitment_url(c)
    assert_response :success
  end

  test "creates a fixed debit commitment" do
    assert_difference -> { @user.commitments.count }, 1 do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "pensão", kind: "fixed", amount_reais: "1.000", schedule_day: 5 },
        instrument: "bank_account-#{@account.id}" }
    end
    c = @user.commitments.last
    assert_equal "fixed", c.kind
    assert_equal @account, c.bank_account
  end

  test "a card installment fans out into posted parcels via Installments::Create" do
    assert_difference -> { @user.transactions.where.not(installment_number: nil).count }, 10 do
      post commitments_url, as: :turbo_stream, params: {
        commitment: { name: "celular", kind: "installment", amount_reais: "500", installments_count: 10, installments_paid: 0 },
        instrument: "credit_card-#{@card.id}" }
    end
    c = @user.commitments.installment.last
    assert_equal 10, c.installments_count
    assert_equal 500_000, c.total_cents
  end

  test "mid-plan já pagas=13 → installment_no(current)=14, progress 13/36, zero transaction rows" do
    post commitments_url, as: :turbo_stream, params: {
      commitment: { name: "carro", kind: "installment", amount_reais: "1.500", installments_count: 36,
                    installments_paid: 13, schedule_day: 10 },
      instrument: "bank_account-#{@account.id}" }
    c = @user.commitments.installment.last
    assert_equal 14, c.installment_no(Date.current.beginning_of_month)
    assert_equal 13, c.paid_count
    assert_equal 0, c.payments.count
  end

  test "destroy hard-deletes with no payments, archives when payments exist" do
    c = @user.commitments.create!(bank_account: @account, name: "x", kind: "fixed", amount_cents: 100, schedule_day: 5, starts_on: Date.current)
    delete commitment_url(c)
    assert_not Commitment.exists?(c.id)

    c2 = @user.commitments.create!(bank_account: @account, name: "y", kind: "fixed", amount_cents: 100, schedule_day: 5, starts_on: Date.current)
    Commitments::MarkPaid.call(c2, Date.current.beginning_of_month)
    delete commitment_url(c2)
    assert Commitment.exists?(c2.id)
    assert c2.reload.archived?
  end

  test "bill-constancy: a card subscription retroactively links its charge; the bill stays constant" do
    month  = @card.billing_month_for(Date.current)
    charge = @user.transactions.create!(credit_card: @card, direction: "expense", status: "posted",
                                        amount_cents: 5_590, occurred_on: Date.current, merchant: "Netflix",
                                        billing_month: month, billing_month_manual: true)
    before = @card.bill_cents(month)
    post commitments_url, as: :turbo_stream, params: {
      commitment: { name: "Netflix", kind: "subscription", amount_reais: "55,90" },
      instrument: "credit_card-#{@card.id}" }
    c = @user.commitments.subscription.last
    assert_equal c.id, charge.reload.commitment_id      # linked at creation (pass 2)
    assert_equal before, @card.bill_cents(month)        # projection swapped for the posted row
  end
end
