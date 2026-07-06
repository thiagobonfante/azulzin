require "test_helper"

class CommitmentOccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst = Institution.find_by(code: "260")
    @account = @user.bank_accounts.create!(institution: @inst)
    @card = @user.credit_cards.create!(institution: @inst, bill_due_day: 10, closing_offset_days: 7)
    @debit = @user.commitments.create!(bank_account: @account, name: "aluguel", kind: "fixed",
                                       amount_cents: 100_000, schedule_day: 5, starts_on: Date.new(2026, 1, 1))
    @sub = @user.commitments.create!(credit_card: @card, name: "Netflix", kind: "subscription",
                                     amount_cents: 5_590, starts_on: Date.new(2026, 1, 1))
    @month = Date.current.beginning_of_month
  end

  def occ(commitment, month) = "#{commitment.id}-#{month.strftime('%Y-%m')}"

  test "paying a debit occurrence records a posted payment named after the commitment" do
    patch pay_commitment_occurrence_url(occ(@debit, @month)), params: { from: "show" }, as: :turbo_stream
    assert_response :success
    assert @debit.paid_in?(@month)
    assert_equal "aluguel", @debit.payments.posted.last.merchant
  end

  test "paying with an adjusted amount records that amount (early/late payment)" do
    patch pay_commitment_occurrence_url(occ(@debit, @month)),
          params: { from: "show", amount_reais: "950,00" }, as: :turbo_stream
    assert_response :success
    assert_equal 95_000, @debit.payments.posted.last.amount_cents
  end

  test "paying from the hub streams the ledger update" do
    patch pay_commitment_occurrence_url(occ(@debit, @month)), params: { from: "hub" }, as: :turbo_stream
    assert_response :success
    assert_match "movements_ledger", response.body
  end

  test "adjusting a card occurrence posts the real charge on that month's fatura" do
    patch pay_commitment_occurrence_url(occ(@sub, @month)),
          params: { from: "show", amount_reais: "107,67" }, as: :turbo_stream
    assert_response :success
    charge = @sub.payments.posted.last
    assert_equal 10_767, charge.amount_cents
    assert_equal @card.id, charge.credit_card_id
    assert_equal @month, charge.billing_month
    # The posted linked charge replaces the projection — the bill shows the adjusted value once.
    assert_equal 10_767, @card.bill_cents(@month)
  end

  test "unpay reverses the payment" do
    Commitments::MarkPaid.call(@debit, @month)
    patch unpay_commitment_occurrence_url(occ(@debit, @month)), as: :turbo_stream
    assert_response :success
    assert_not @debit.paid_in?(@month)
  end

  test "cannot pay another user's commitment occurrence" do
    other = User.create!(email_address: "z@example.com", password: "password123")
    theirs = other.commitments.create!(bank_account: other.bank_accounts.create!(institution: @inst),
                                       name: "x", kind: "fixed", amount_cents: 100, schedule_day: 5, starts_on: Date.current)
    patch pay_commitment_occurrence_url(occ(theirs, @month)), params: { from: "show" }, as: :turbo_stream
    assert_response :not_found
  end
end
