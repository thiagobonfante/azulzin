require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:confirmed)
    @user.update!(name: "Ana", phone: "5511912345678", onboarded_at: Time.current)
    sign_in_as(@user)
    @inst    = Institution.find_by(code: "260")
    @account = @user.bank_accounts.create!(institution: @inst, nickname: "Salário")
    @card    = @user.credit_cards.create!(institution: @inst, nickname: "Roxinho")
  end

  def pending_txn(**attrs)
    @user.transactions.create!({ amount_cents: 1_323, occurred_on: Date.current, status: "pending_review" }.merge(attrs))
  end

  test "index requires a completed onboarding" do
    @user.update!(onboarded_at: nil)
    get transactions_url
    assert_redirected_to onboarding_url
  end

  test "index lists the user's pending + posted-unassigned rows, scoped to the user" do
    mine  = pending_txn
    other = User.create!(email_address: "other@example.com", password: "password123")
    theirs = other.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")

    get transactions_url
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(mine)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(theirs)}", count: 0
  end

  test "assign charges the expense to the chosen account (assign_instrument!)" do
    txn = pending_txn
    patch assign_transaction_url(txn), params: { instrument: "bank_account-#{@account.id}" }
    assert_redirected_to transactions_path
    assert_equal @account, txn.reload.bank_account
    assert_nil txn.credit_card
  end

  test "assign with a blank instrument clears any assignment" do
    txn = pending_txn(bank_account: @account)
    patch assign_transaction_url(txn), params: { instrument: "" }
    assert_nil txn.reload.bank_account
    assert_nil txn.credit_card
  end

  test "confirm posts a pending transaction" do
    txn = pending_txn
    patch confirm_transaction_url(txn)
    assert txn.reload.posted?
    assert txn.confirmed_at.present?
  end

  test "update edits the amount and merchant" do
    txn = pending_txn
    patch transaction_url(txn), params: { transaction: { amount_reais: "50,00", merchant: "Padaria" } }
    txn.reload
    assert_equal 5_000, txn.amount_cents
    assert_equal "Padaria", txn.merchant
  end

  test "destroy reverses a posted transaction (reverse!)" do
    txn = pending_txn(status: "posted", bank_account: @account)
    delete transaction_url(txn)
    assert txn.reload.rejected?
  end

  test "cannot touch another user's transaction" do
    other = User.create!(email_address: "other2@example.com", password: "password123")
    theirs = other.transactions.create!(amount_cents: 500, occurred_on: Date.current, status: "pending_review")
    patch confirm_transaction_url(theirs)
    assert_response :not_found
    assert theirs.reload.pending_review?
  end

  test "assign answers a turbo stream" do
    txn = pending_txn
    patch assign_transaction_url(txn), params: { instrument: "credit_card-#{@card.id}" }, as: :turbo_stream
    assert_response :success
    assert_equal @card, txn.reload.credit_card
  end
end
