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

    # "parcela"/"conta"/… carry no identity — a bare "paguei a parcela" must pick, not miss.
    GENERIC_WORDS = %w[a o do da de na no parcela parcelas prestacao conta boleto fatura
                       compromisso assinatura ultima ultimo].freeze

    def call
      candidates = account.commitments.kept.active.select { |c| c.active_in?(base_month) }
      return reply("commitment_not_found") if candidates.empty?
      # No identifying words ("paguei a parcela") → a sole candidate self-picks, several
      # get the numbered pick — never commitment_not_found while candidates exist.
      if core_phrase.blank?
        pool = mentions_installment? ? candidates.select(&:installment?).presence || candidates : candidates
        return pool.size == 1 ? proceed(pool.first) : ask_pick(pool)
      end

      scored = candidates.map { |c| [ c, similarity(c) ] }.sort_by { |(_, s)| -s }
      top, top_score = scored.first
      second = scored[1]&.last || 0.0

      return reply("commitment_not_found") if top_score < 0.60
      if (top_score - second) < 0.15 && scored.count { |(_, s)| (top_score - s) < 0.15 } > 1
        return ask_pick(scored.map(&:first))
      end

      proceed(top)
    end

    private

    # The phrase minus filler/generic words — "última parcela do sofá" keys on "sofa".
    def core_phrase
      @core_phrase ||= (Whatsapp.normalize(@extraction.commitment_phrase.to_s).split - GENERIC_WORDS).join(" ")
    end

    def mentions_installment? = transcript.match?(/parcela|presta[cç]/) ||
                            Whatsapp.normalize(@extraction.commitment_phrase.to_s).match?(/parcela|prestac/)

    def transcript = @transcript ||= Whatsapp.normalize(@extraction.raw.is_a?(Hash) ? @extraction.raw["transcript"].to_s : "")

    # "paguei a ÚLTIMA parcela" targets the plan's final month.
    def last_parcel? = transcript.match?(/\bultim/)

    def explicit_month
      return nil if @extraction.target_bill_raw.blank?
      Whatsapp::MonthPhrase.parse(@extraction.target_bill_raw, reference: sp_today)
    end

    def base_month = @base_month ||= (explicit_month || sp_today.beginning_of_month)

    def target_month_for(commitment)
      return commitment.last_month.beginning_of_month if last_parcel? && commitment.installment? && commitment.last_month
      base_month
    end

    # Token/substring-aware — "carro" should match "carro financiado" even though full-string
    # trigram similarity is penalised by the length gap.
    def similarity(commitment)
      phrase = core_phrase
      name   = Whatsapp.normalize(commitment.name)
      return 0.0 if phrase.blank?
      return 1.0 if name.include?(phrase) && phrase.length >= 3
      token_best = phrase.split.flat_map { |a| name.split.map { |b| Whatsapp.similarity(a, b) } }.max || 0.0
      [ Whatsapp.similarity(phrase, name), token_best ].max
    end

    def proceed(commitment)
      month = target_month_for(commitment)
      return reply("commitment_on_bill", instrument: commitment.credit_card.display_name, name: commitment.name) if commitment.card?
      return reply("commitment_already_paid", name: commitment.name, month: month_label(month)) if commitment.paid_in?(month)
      # A future parcel can carry a different amount (early-payoff discount) — confirm the
      # value first; ReplyRouter#resolve_commitment_pay_confirm takes sim/confirmo or a number.
      return ask_pay_confirm(commitment, month) if month > sp_today.beginning_of_month
      pay(commitment, month)
    end

    def pay(commitment, month)
      amount = (Money.to_cents(@extraction.amount_raw) if @extraction.amount_present?)
      txn = Commitments::MarkPaid.call(commitment, month, amount: amount, created_by: @msg.user,
                                       source_message_id: @msg.wa_message_id, whatsapp_message: @msg)
      if commitment.completed?
        reply("commitment_completed", txn: txn, name: commitment.name, amount: currency(txn.amount_cents),
              month: month_label(month), count: commitment.installments_count)
      elsif commitment.installment?
        # remaining = parcels actually unpaid, never positional (paying the última out of
        # order must not read "faltam 0" while earlier parcels are open).
        remaining = commitment.installments_count - commitment.paid_count
        reply("commitment_paid", txn: txn, name: commitment.name, amount: currency(txn.amount_cents),
              month: month_label(month), remaining: remaining, count: commitment.installments_count)
      else
        reply("commitment_paid_simple", txn: txn, name: commitment.name, amount: currency(txn.amount_cents), month: month_label(month))
      end
      txn
    end

    def ask_pay_confirm(commitment, month)
      stub = Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.account = account; t.created_by = @msg.user; t.whatsapp_message = @msg; t.source = @extraction.source
        t.amount_cents = 0; t.direction = "expense"; t.status = "needs_disambiguation"
        t.occurred_on = sp_today; t.billing_month = month
        t.ask = { "slot" => "commitment_pay_confirm", "commitment_id" => commitment.id,
                  "month" => month.strftime("%Y-%m-%d"), "expected_cents" => commitment.amount_cents }
        t.ask_expires_at = 60.minutes.from_now
      end
      reply("ask_pay_confirm", txn: stub, name: commitment.name, month: month_label(month),
            amount: currency(commitment.amount_cents))
      stub
    end

    def ask_pick(commitments)
      options = commitments.first(5)
      stub = Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.account = account; t.created_by = @msg.user; t.whatsapp_message = @msg; t.source = @extraction.source
        t.amount_cents = 0; t.direction = "expense"; t.status = "needs_disambiguation"
        t.occurred_on = sp_today; t.billing_month = sp_today.beginning_of_month
        t.ask = { "slot" => "commitment_pick", "options" => options.map(&:id),
                  "month" => base_month.strftime("%Y-%m-%d"), "last_parcel" => last_parcel? }
        t.ask_expires_at = 60.minutes.from_now
      end
      reply("ask_commitment_pick", txn: stub, options: options.each_with_index.map { |c, i| "#{i + 1}. #{c.name}" }.join("\n"))
      stub
    end
  end
end
