module Whatsapp
  # query intent (07 §4.9): read-only. Zero Transaction writes, zero asks — an unresolvable
  # instrument answers the broader question. Composes over the same read layer as the hub.
  class QueryAnswerer
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      case @extraction.query_kind
      when "account_balance" then answer_balance
      when "card_bill"       then answer_card_bill
      when "savings_total"   then answer_savings
      else                        answer_month
      end
    end

    private

    def month = @month ||= Whatsapp::MonthPhrase.parse(@extraction.target_bill_raw, reference: sp_today)
    def now_summary = @now_summary ||= MonthSummary.new(account, sp_today.beginning_of_month)

    def answer_month
      s = MonthSummary.new(account, month)
      key = s.in_the_blue? ? "month_answer_blue" : "month_answer_red"
      reply(key, month: month_label(s.month), remaining: currency(s.remaining_cents),
            incomes: currency(s.incomes_cents), expenses: currency(s.expenses_cents), bills: currency(s.bills_cents))
    end

    def answer_balance
      s = now_summary
      lines = account.bank_accounts.kept.includes(:institution).order(:created_at).map do |a|
        I18n.with_locale(user.locale) do
          I18n.t("whatsapp.replies.balance_line", name: a.display_name, amount: currency(s.account_balances[a.id].to_i))
        end
      end.join("\n")
      reply("balance_answer", lines: lines, total: currency(s.accounts_total_cents))
    end

    def answer_card_bill
      card = Whatsapp::Matcher.new(account, @extraction).call.instrument
      card = account.credit_cards.kept.first unless card.is_a?(CreditCard)
      return answer_month if card.nil?
      m = card.billing_configured? ? card.current_open_bill_month : sp_today.beginning_of_month
      reply("card_bill_answer", name: card.display_name, month: month_label(m), amount: currency(card.bill_cents(m)),
            closes: (card.billing_configured? ? card.closing_date(m).day : "—"), due: (card.bill_due_day || "—"))
    end

    def answer_savings
      s = now_summary
      reply("savings_answer", total: currency(s.saved_total_cents), month: currency(s.saved_cents))
    end
  end
end
