module Whatsapp
  # pay_commitment intent (07 §4.5): flags a debit commitment paid via the SAME command as the
  # hub's Pagar button (Commitments::MarkPaid). Card-charged commitments settle on the bill (no
  # payment row ever). Idempotent — a repeat month is a friendly already-paid reply, no row.
  class PayCommitmentDecider
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      month = Whatsapp::MonthPhrase.parse(@extraction.target_bill_raw, reference: sp_today)
      candidates = account.commitments.kept.active.select { |c| c.active_in?(month) }
      scored = candidates.map { |c| [ c, similarity(c) ] }.sort_by { |(_, s)| -s }
      top, top_score = scored.first || [ nil, 0.0 ]
      second = scored[1]&.last || 0.0

      return reply("commitment_not_found") if top.nil? || top_score < 0.60
      return ask_pick(scored, month) if (top_score - second) < 0.15 && scored.count { |(_, s)| (top_score - s) < 0.15 } > 1

      pay(top, month)
    end

    private

    # Token/substring-aware — "carro" should match "carro financiado" even though full-string
    # trigram similarity is penalised by the length gap.
    def similarity(commitment)
      phrase = Whatsapp.normalize(@extraction.commitment_phrase.to_s)
      name   = Whatsapp.normalize(commitment.name)
      return 0.0 if phrase.blank?
      return 1.0 if name.include?(phrase) && phrase.length >= 3
      token_best = phrase.split.flat_map { |a| name.split.map { |b| Whatsapp.similarity(a, b) } }.max || 0.0
      [ Whatsapp.similarity(phrase, name), token_best ].max
    end

    def pay(commitment, month)
      return reply("commitment_on_bill", instrument: commitment.credit_card.display_name, name: commitment.name) if commitment.card?
      return reply("commitment_already_paid", name: commitment.name, month: month_label(month)) if commitment.paid_in?(month)

      amount = (Money.to_cents(@extraction.amount_raw) if @extraction.amount_present?)
      txn = Commitments::MarkPaid.call(commitment, month, amount: amount, created_by: @msg.user,
                                       source_message_id: @msg.wa_message_id, whatsapp_message: @msg)
      if commitment.installment?
        remaining = commitment.installments_count - commitment.installment_no(month)
        reply("commitment_paid", txn: txn, name: commitment.name, amount: currency(txn.amount_cents),
              month: month_label(month), remaining: remaining, count: commitment.installments_count)
      else
        reply("commitment_paid_simple", txn: txn, name: commitment.name, amount: currency(txn.amount_cents), month: month_label(month))
      end
      txn
    end

    def ask_pick(scored, month)
      options = scored.map(&:first).first(5)
      stub = Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.account = account; t.created_by = @msg.user; t.whatsapp_message = @msg; t.source = @extraction.source
        t.amount_cents = 0; t.direction = "expense"; t.status = "needs_disambiguation"
        t.occurred_on = sp_today; t.billing_month = sp_today.beginning_of_month
        t.ask = { "slot" => "commitment_pick", "options" => options.map(&:id), "month" => month.strftime("%Y-%m-%d") }
        t.ask_expires_at = 60.minutes.from_now
      end
      reply("ask_commitment_pick", txn: stub, options: options.each_with_index.map { |c, i| "#{i + 1}. #{c.name}" }.join("\n"))
      stub
    end
  end
end
