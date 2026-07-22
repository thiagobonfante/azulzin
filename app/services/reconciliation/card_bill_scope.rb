module Reconciliation
  # The app-side of a card-bill diff: the fatura's posted rows for (card, month). Works
  # off the pair — an old query-only month reconciles without needing its CardBill row.
  class CardBillScope
    attr_reader :credit_card, :month

    def initialize(credit_card:, month:)
      @credit_card = credit_card
      @month       = month.beginning_of_month
    end

    # ponytail: phase 6 widens credit_card_id to the family (root + sub-cards).
    def transactions
      credit_card.transactions.posted.kept.where(billing_month: @month)
                 .includes(:commitment).order(:occurred_on, :id)
    end

    # only_in_app proposes MOVE to the next fatura (the sticky manual move).
    def move_month = @month >> 1

    # Card rows are already the extrato's expense/estorno view.
    def direction_of(txn) = txn.direction

    def creation_attributes(_row)
      # The bank put it on THIS bill — pin it there, never re-bucket.
      { credit_card: @credit_card, billing_month: @month, billing_month_manual: true }
    end

    def resolve_app_only!(txn, by: nil)
      txn.update!(billing_month: move_month, billing_month_manual: true)
    end
  end
end
