module Exports
  # Row builder over the account's posted, kept movements for a from/to date range on
  # occurred_on — the axis a person means by "January" — with billing_month riding along
  # as its own labelled column (card users need both). Reads in PK batches (find_each)
  # into light structs, then a stable occurred_on sort — never an unbounded AR load.
  class Ledger
    Row = Struct.new(:occurred_on, :billing_month, :description, :category, :kind,
                     :direction, :amount_cents, :instrument, :status, keyword_init: true)

    attr_reader :account, :from, :to

    def initialize(account, from: nil, to: nil)
      @account = account
      @from    = from
      @to      = to
    end

    def rows
      @rows ||= begin
        built = []
        scope.find_each { |transaction| built << build_row(transaction) }
        built.each_with_index.sort_by { |row, index| [ row.occurred_on, index ] }.map(&:first)
      end
    end

    # Labelled totals for XLSX/PDF (signed cents). The hub treats an internal transfer as
    # neutral (MonthSummary counts savings via guardado), so Resultado excludes transfers —
    # entradas + saídas only. Transfers get their own labelled figure instead of silently
    # deflating the number a person reconciles against the hub.
    def income_cents   = direction_cents("income")
    def expense_cents  = direction_cents("expense")
    def transfer_cents = direction_cents("transfer")
    def result_cents   = income_cents + expense_cents

    private
      def direction_cents(direction)
        rows.sum { |row| row.direction == direction ? row.amount_cents : 0 }
      end

      def scope
        base = account.transactions.posted.kept
                      .includes(:category, :bank_account, :credit_card, :commitment,
                                :transfer_to_bank_account, :transfer_to_credit_card)
        (from || to) ? base.where(occurred_on: from..to) : base
      end

      def build_row(transaction)
        Row.new(
          occurred_on:   transaction.occurred_on,
          billing_month: transaction.billing_month,
          description:   transaction.merchant.presence || transaction.description.presence ||
                         transaction.commitment&.name,
          category:      transaction.category&.name,   # dead rows keep their name — the history snapshot
          kind:          I18n.t("exports.ledger.kinds.#{transaction.direction}"),
          direction:     transaction.direction,
          amount_cents:  signed_cents(transaction),
          instrument:    instrument_label(transaction),
          status:        I18n.t("transactions.statuses.#{transaction.status}")
        )
      end

      # Signed: money in +, money out − (a transfer leaves the source account, so −).
      def signed_cents(transaction)
        transaction.income? ? transaction.amount_cents : -transaction.amount_cents
      end

      def instrument_label(transaction)
        if transaction.transfer?
          [ transaction.bank_account&.display_name,
            (transaction.transfer_to_bank_account || transaction.transfer_to_credit_card)&.display_name ].compact.join(" → ")
        else
          transaction.instrument&.display_name
        end
      end
  end
end
