require "test_helper"

class CommitmentOccurrenceTest < ActiveSupport::TestCase
  setup do
    @user = users(:confirmed)
    @bank = BankAccount.create!(account: @user.account, institution: Institution.find_by(code: "260"))
  end

  test "history_for renders a parcel paid beyond the 12-month horizon (advanced última)" do
    plan = Commitment.create!(account: @user.account, bank_account: @bank, name: "Carro",
                              kind: "installment", amount_cents: 65_000, total_cents: 65_000 * 36,
                              installments_count: 36, schedule_kind: "fixed_day", schedule_day: 5,
                              starts_on: Date.current.beginning_of_month << 10)
    last = plan.last_month.beginning_of_month   # 25 months out — beyond current + 12
    Commitments::MarkPaid.call(plan, last, amount: 38_000, created_by: @user)

    occurrences = CommitmentOccurrence.history_for(plan)

    horizon = Date.current.beginning_of_month >> 12
    assert occurrences.none? { |o| o.month > horizon && !o.paid? },
           "unpaid months beyond the horizon stay trimmed"
    ultima = occurrences.find { |o| o.month == last }
    assert ultima, "the paid última must render even beyond the 12-month horizon"
    assert ultima.paid?
    assert_equal 38_000, ultima.payment.amount_cents
  end
end
