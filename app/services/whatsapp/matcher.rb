module Whatsapp
  # Resolves an extracted instrument phrase ("no cartão Nubank", "final 1234") to ONE of
  # this user's bank accounts / credit cards. Per-user candidate sets are tiny (2–15 rows)
  # so everything is scored in Ruby — no index, no gem (hand-rolled similarity). The KIND
  # (débito vs crédito) keyword layer filters which instruments are eligible. See
  # .plans/whats §4.6.
  class Matcher
    Result = Struct.new(:instrument, :candidates, :c_match, :reason, keyword_init: true) do
      def matched?    = instrument.present?
      def ambiguous?  = reason == "needs_disambiguation"
    end

    FILLER = %w[banco cartao conta de do da no na meu minha pelo pela com a o para].to_set.freeze
    CREDIT_RE = /cart[aã]o|cr[eé]dito|fatura|parcelad/i
    DEBIT_RE  = /d[eé]bito|conta|pix|boleto|ted|doc/i
    # R4 keyword layer: a savings/caixinha phrase narrows candidates to savings accounts.
    SAVINGS_RE = /caixinha|poupan[cç]a|reserva|cofrinho|guardad/i

    def initialize(user, extraction, restrict_kind: nil)
      @user = user
      @extraction = extraction
      @restrict_kind = restrict_kind   # :account restricts to bank accounts (transfer legs)
    end

    # Public entry for resolving a single phrase to an instrument (07 §3): used by transfers
    # (source + destination), passing kind: :account (cards are never transfer legs).
    def self.match_phrase(user, phrase, payment_method: nil, kind: nil)
      ex = Extraction.new(instrument_phrase: phrase, payment_method: payment_method || "desconhecido")
      new(user, ex, restrict_kind: kind).call
    end

    def call
      phrase = normalize_phrase(@extraction.instrument_phrase)
      return kind_only_match if phrase.blank?   # receipts: no nickname, but débito/crédito is decisive

      cands = candidates_for_kind
      return miss("no_such_instrument", c: 0.20) if cands.empty?

      scored = cands.map { |c| [ c, score(phrase, c) ] }.sort_by { |(_, s)| -s }
      top, top_score = scored.first
      second_score = scored[1]&.last || 0.0
      margin = top_score - second_score

      classify(top, top_score, margin, scored)
    end

    private

    TIE = 0.15

    def classify(top, top_score, _margin, scored)
      return miss("no_such_instrument", c: 0.20) if top_score < 0.60

      # A near-tie among ≥2 instruments is checked FIRST — even two exact (1.0) matches must
      # disambiguate rather than silently pick one (e.g. two cards at the same bank).
      tied = scored.select { |(_, s)| (top_score - s) < TIE }.map { |(c, _)| c[:record] }
      if tied.size >= 2
        return Result.new(instrument: nil, candidates: tied, c_match: 0.40, reason: "needs_disambiguation")
      end

      c, reason =
        if    top_score >= 0.999 then [ 1.0,  "exact" ]
        elsif top_score >= 0.90  then [ 0.85, "fuzzy_strong" ]
        elsif top_score >= 0.75  then [ 0.70, "fuzzy_weak" ]
        else                          [ 0.65, "fuzzy_weak" ]
        end
      Result.new(instrument: top[:record], candidates: scored, c_match: c, reason: reason)
    end

    def miss(reason, c: 0.0) = Result.new(instrument: nil, candidates: [], c_match: c, reason: reason)

    # No instrument named (typical for a receipt) — auto-pick ONLY when the payment method
    # is a decisive KIND (débito xor crédito) and the user has exactly one instrument of
    # that kind. Otherwise leave it unassigned for the user to pick in-app.
    def kind_only_match
      return miss("instrument_missing") unless kind_decisive?
      cands = candidates_for_kind
      return miss("instrument_missing") unless cands.size == 1
      Result.new(instrument: cands.first[:record], candidates: cands, c_match: 0.70, reason: "kind_only")
    end

    def kind_decisive?
      pm = @extraction.payment_method.to_s
      pm.match?(CREDIT_RE) ^ pm.match?(DEBIT_RE)
    end

    # Which instruments are eligible given the KIND keywords (deterministic, more reliable
    # than the LLM on this axis). credito → cards; debito/pix/boleto → accounts; else both.
    def candidates_for_kind
      text = "#{@extraction.instrument_phrase} #{@extraction.payment_method}"
      accounts = @user.bank_accounts.includes(:institution)
      accounts = accounts.where(kind: "savings") if SAVINGS_RE.match?(@extraction.instrument_phrase.to_s)
      cards    = @user.credit_cards.includes(:institution)
      list =
        if @restrict_kind == :account then accounts
        elsif text.match?(CREDIT_RE) && !text.match?(DEBIT_RE) then cards
        elsif text.match?(DEBIT_RE) && !text.match?(CREDIT_RE) then accounts
        else accounts.to_a + cards.to_a
        end
      list.map { |record| { record: record, terms: term_bag(record) } }
    end

    # Normalized term bag for an instrument: nickname + institution name/initials + aliases
    # (+ last-4 for cards). `short` terms (≤ SHORT_ALIAS_MAX) match as whole tokens only.
    def term_bag(record)
      inst = record.institution
      raw = [ record.nickname, inst.name, inst.initials, *Whatsapp.aliases_for(inst.code) ]
      raw << record.last4 if record.respond_to?(:last4) && record.last4.present?
      raw.compact.map { |t| Whatsapp.normalize(t) }.reject(&:blank?).uniq
    end

    def normalize_phrase(phrase)
      Whatsapp.normalize(phrase).split.reject { |tok| FILLER.include?(tok) }.join(" ")
    end

    # Max term similarity between the phrase (and its tokens) and the instrument's terms.
    def score(phrase, candidate)
      tokens = phrase.split
      candidate[:terms].map { |term| term_sim(phrase, tokens, term) }.max || 0.0
    end

    def term_sim(phrase, tokens, term)
      return 1.0 if phrase == term || tokens.include?(term)
      # Short brand tokens (bb, nu, c6, mp): whole-token match only — never fuzzy.
      return 0.0 if term.length <= Whatsapp::SHORT_ALIAS_MAX
      best = tokens.map { |tok| Whatsapp.similarity(tok, term) }.max || 0.0
      [ best, Whatsapp.similarity(phrase, term) ].max
    end
  end
end
