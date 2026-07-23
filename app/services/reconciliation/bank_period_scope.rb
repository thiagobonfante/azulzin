module Reconciliation
  # The app-side of a bank-extrato diff (.plans/credit-cards 03 §2): the account's posted
  # rows in the statement month — including transfer legs, which the extrato sees as
  # ordinary debits/credits (the incoming side lives on transfer_to_bank_account_id, so
  # it is unioned in; direction_of normalizes both to the extrato's expense/income view).
  class BankPeriodScope
    attr_reader :bank_account, :month

    def initialize(bank_account:, month:)
      @bank_account = bank_account
      @month        = month.beginning_of_month
    end

    def transactions
      range = @month..@month.end_of_month
      own = @bank_account.transactions.posted.kept.where(occurred_on: range)
      incoming = @bank_account.incoming_transfers.posted.kept.where(occurred_on: range)
      (own.to_a + incoming.to_a).sort_by { |t| [ t.occurred_on, t.id ] }
    end

    # How the extrato reads this row: an outgoing transfer is a debit, an incoming one a
    # credit; card rows never appear here (the fatura payment's source leg does, as out).
    def direction_of(txn)
      return txn.direction unless txn.transfer?
      txn.bank_account_id == @bank_account.id && txn.transfer_to_bank_account_id != @bank_account.id ? "expense" : "income"
    end

    def creation_attributes(row)
      { bank_account: @bank_account }   # billing_month = calendar month via the callback
    end

    # only_in_app on the bank side = a probable duplicate/wrong entry → soft delete
    # (default in the UI is "manter" — the checkbox opts in).
    def resolve_app_only!(txn, by:)
      txn.soft_delete!(by: by)
    end
  end
end
