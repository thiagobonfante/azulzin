module Whatsapp
  # Turns an extraction + match + confidence into an outcome, per the DECIDED silent
  # auto-commit posture (Open Decision #5):
  #   - amount present & confidence ≥ floor & instrument matched strongly → POST assigned
  #   - amount present & confidence ≥ floor & instrument unknown/weak      → POST unassigned
  #   - amount present & confidence < floor                               → PARK (pending_review)
  #   - amount missing                                                    → ASK "quanto foi?"
  # The transaction is idempotent on source_message_id. See .plans/whats §4.7 / §5.
  class Decider
    ASK_TTL = 60.minutes
    RECEIPT_MATCH_DAYS = 3

    def initialize(msg, extraction, match, confidence)
      @msg = msg
      @extraction = extraction
      @match = match
      @confidence = confidence
    end

    def call
      return ask_amount unless @extraction.amount_present?
      # A receipt exactly matching a recent posted row is its own confidence proof —
      # reconcile BEFORE the floor gate (a parked duplicate of an already-posted expense
      # helps no one; the extracted amount is validated by the row it matches).
      if (existing = reconcile_receipt(assignable_instrument))
        kind = existing.credit_card ? "card" : "account"
        reply("whatsapp.replies.receipt_matched_#{kind}", existing,
              amount: currency, instrument: (existing.credit_card || existing.bank_account).display_name)
        return existing
      end
      # Same thing, same day, already posted → confirm before stacking a silent duplicate
      # (a re-sent receipt, or "café 5" texted twice). Below the floor it parks anyway —
      # the review tray IS the confirmation there.
      if @confidence.above_floor? && (dup = duplicate_suspect)
        return ask_duplicate(dup)
      end
      @confidence.above_floor? ? post : park
    end

    private

    def post
      instrument = assignable_instrument
      # A known payment method narrows the instrument set (credito → cards, debito/pix →
      # accounts): a sole candidate assigns silently; several get ONE numbered ask instead
      # of an unassigned row in the review inbox. Unknown method keeps the unassigned post.
      if instrument.nil? && (candidates = method_candidates).any?
        return ask_instrument_pick(candidates) if candidates.size > 1
        instrument = candidates.first
      end
      txn = upsert(status: "posted", confirmed_at: Time.current, instrument: instrument)
      # Naming the auto-assigned category in the reply is the cheap correction loop (O2):
      # a wrong silent category becomes visible immediately, not at month-end. The key forks
      # on cartão vs conta (pt-BR gendered contractions rule out a %{kind} interpolation).
      kind = instrument.is_a?(CreditCard) ? "card" : "account"
      if instrument && txn.category
        reply("whatsapp.replies.posted_#{kind}_categorized", txn,
              amount: currency, instrument: instrument.display_name, category: txn.category.name)
      elsif instrument
        reply("whatsapp.replies.posted_#{kind}", txn,
              amount: currency, instrument: instrument.display_name)
      else
        reply("whatsapp.replies.posted_unassigned", txn, amount: currency)
      end
      txn
    end

    def park
      # Keep the instrument match: a below-floor receipt lands in the tray PRE-ROUTED (and a
      # parked card row buckets billing_month by the card's closing rule, like a posted one).
      txn = upsert(status: "pending_review", instrument: assignable_instrument)
      reply("whatsapp.replies.parked", txn)
      txn
    end

    # Amount unreadable — the ONE WhatsApp question we keep. Store a placeholder open-ask
    # row (amount 0) carrying the already-resolved instrument, so the user's next reply
    # only needs to supply the amount.
    def ask_amount
      txn = upsert(status: "needs_clarification", amount_cents: 0,
                   instrument: assignable_instrument,
                   ask: { "slot" => "amount" }, ask_expires_at: ASK_TTL.from_now)
      reply("whatsapp.replies.clarify_amount", txn)
      txn
    end

    def assignable_instrument
      return nil unless @match.matched? && @match.c_match >= Transaction::MATCH_ASSIGN_MIN
      @match.instrument
    end

    # A posted expense with the same cents on the same day: for text the merchant must also
    # match (two different R$ 5 buys a day are normal); a receipt's exact amount+day alone
    # is suspicious enough (the reconcile above already merged the receipt-less case).
    def duplicate_suspect
      on = @extraction.occurred_on || today
      scope = account.transactions.kept.where(status: "posted", direction: "expense",
                                              amount_cents: @extraction.amount_cents, occurred_on: on)
      merchant = Whatsapp.normalize(@extraction.merchant.to_s)
      if merchant.present?
        found = scope.detect { |t| Whatsapp.normalize(t.merchant.to_s) == merchant }
        return found if found
      end
      @extraction.source == "whatsapp_receipt" ? scope.first : nil
    end

    def ask_duplicate(dup)
      txn = upsert(status: "needs_disambiguation", instrument: assignable_instrument,
                   ask: { "slot" => "duplicate_confirm" }, ask_expires_at: ASK_TTL.from_now)
      label = dup.merchant.presence || (dup.credit_card || dup.bank_account)&.display_name
      reply("whatsapp.replies.ask_duplicate", txn, amount: currency,
            label: label || I18n.t("whatsapp.replies.no_description", locale: @msg.user.locale))
      txn
    end

    def method_candidates = self.class.method_candidates(account, @extraction)

    # Class-level so MultiExpenseHandler narrows each batch item with the exact same rules.
    def self.method_candidates(account, extraction)
      case extraction.payment_method
      when "credito"       then cards(account)
      when "debito", "pix" then checking_accounts(account)
      else phrase_candidates(account, extraction)
      end
    end

    # "no cartão" without crédito/débito: the model honestly leaves payment_method
    # desconhecido, but the phrase still narrows — in this app "cartão" IS a credit-card
    # row (débito rides the bank account), and a bare "conta" means a checking account.
    def self.phrase_candidates(account, extraction)
      phrase = Whatsapp.normalize(extraction.instrument_phrase.to_s)
      return cards(account)             if phrase.include?("cartao")
      return checking_accounts(account) if phrase.include?("conta")
      []
    end

    def self.cards(account)             = account.credit_cards.kept.order(:created_at).to_a
    def self.checking_accounts(account) = account.bank_accounts.kept.where.not(kind: "savings").order(:created_at).to_a

    # Same open-ask machinery as ask_amount; the answer routes zero-LLM through ReplyRouter
    # (a leading index or a fuzzy name against the stored prompt-ordered options).
    def ask_instrument_pick(candidates)
      kind = candidates.first.is_a?(CreditCard) ? "card" : "account"
      txn = upsert(status: "needs_clarification",
                   ask: { "slot" => "instrument_pick", "kind" => kind,
                          "options" => candidates.map(&:id) },
                   ask_expires_at: ASK_TTL.from_now)
      options = candidates.each_with_index.map { |c, i| "#{i + 1}. #{c.display_name}" }.join("\n")
      reply("whatsapp.replies.ask_#{kind}_pick", txn, amount: currency, options: options)
      txn
    end

    def currency = WhatsappReply.currency(@extraction.amount_cents, locale: @msg.user.locale)

    def upsert(status:, instrument: nil, amount_cents: nil, ask: {}, ask_expires_at: nil, **_)
      self.class.write(msg: @msg, account: account, extraction: @extraction,
                       confidence_score: @confidence.capture_score,
                       match_meta: { "reason" => @match.reason, "c_match" => @match.c_match },
                       source_message_id: @msg.wa_message_id,
                       status: status, instrument: instrument, amount_cents: amount_cents,
                       ask: ask, ask_expires_at: ask_expires_at)
    end

    # The one expense write site, class-level so MultiExpenseHandler posts each batch item
    # through the exact same money path (billing_month, auto-categorize, commitment link).
    # Idempotent on source_message_id (batch items pass a "#index"-suffixed id).
    def self.write(msg:, account:, extraction:, confidence_score:, match_meta:,
                   source_message_id:, status:, instrument: nil, amount_cents: nil,
                   ask: {}, ask_expires_at: nil)
      Transaction.find_or_create_by!(source_message_id: source_message_id) do |t|
        t.account          = account       # D2: tenancy (nil fallback), NOT raw msg.account
        t.created_by       = msg.user      # D7: attribution — explicit, never Current.user (job)
        t.whatsapp_message = msg
        t.amount_cents     = amount_cents || extraction.amount_cents
        t.merchant         = extraction.merchant
        t.payment_method   = extraction.payment_method
        t.occurred_on      = extraction.occurred_on || today
        # Explicit billing_month write site (02 §3.2-1): the closing rule for a matched card,
        # calendar month otherwise. Computed here, not left solely to the before_validation net.
        t.billing_month    = billing_month_for(instrument, t.occurred_on)
        # R6: memory → LLM label resolved in Ruby (≥ MATCH_MIN), never an LLM id.
        t.category_id, t.category_source =
          Categories.auto_assign(account: account, merchant: extraction.merchant, label: extraction.category)
        t.status           = status
        t.confirmed_at     = (Time.current if status == "posted")
        t.source           = extraction.source
        t.confidence       = confidence_score
        t.extraction       = extraction.to_h.compact
        t.match_meta       = match_meta
        t.ask              = ask
        t.ask_expires_at   = ask_expires_at
        assign_instrument(t, instrument)
        # Capture-time subscription reconciliation (05 §5.7 pass 1): a posted card charge similar
        # to an active card subscription/fixed commitment on that card adopts its commitment_id,
        # so the bill projection drops out (no double-count).
        t.commitment_id = link_card_commitment(t) if status == "posted" && instrument.is_a?(CreditCard)
      end
    end

    # "Whose stuff?" → account (spine D6), with the deploy-window nil fallback (doc 04 §3.1/§4).
    def account
      return @msg.account if @msg.account
      @msg.account = @msg.user&.account
      @msg.save! if @msg.account && @msg.persisted?
      @msg.account
    end

    def self.link_card_commitment(txn)
      card = txn.credit_card
      return nil unless card
      candidates = card.commitments.kept.active.select do |c|
        %w[subscription fixed].include?(c.kind) && c.active_in?(txn.billing_month) &&
          !c.paid_in?(txn.billing_month) && amount_close?(txn.amount_cents, c.amount_cents)
      end
      best = candidates.max_by { |c| Whatsapp.similarity(Whatsapp.normalize(txn.merchant.to_s), Whatsapp.normalize(c.name)) }
      return nil unless best && Whatsapp.similarity(Whatsapp.normalize(txn.merchant.to_s), Whatsapp.normalize(best.name)) >= Transaction::MATCH_ASSIGN_MIN
      best.id
    end

    def self.amount_close?(a, b)
      tol = [ (b.to_i * 0.2).round, 500 ].max
      (a.to_i - b.to_i).abs <= tol
    end

    # Receipt↔transaction reconciliation (the receipt sibling of link_card_commitment):
    # a receipt matching an already-posted charge attaches to that row instead of posting a
    # duplicate. Conservative on purpose — exact amount + ±3 days + receipt-less rows only;
    # an instrument match takes the strongest candidate, while a receipt with NO instrument
    # hint (a plain recibo names no bank) merges only when the account-wide match is UNIQUE
    # and the row carries an instrument.
    def reconcile_receipt(instrument)
      return nil unless @extraction.source == "whatsapp_receipt"
      on = @extraction.occurred_on || today
      base = instrument ? instrument.transactions :
               account.transactions.where("bank_account_id IS NOT NULL OR credit_card_id IS NOT NULL")
      scope = base.kept.where(
        account: account, status: "posted", direction: "expense",
        amount_cents: @extraction.amount_cents,
        occurred_on: (on - RECEIPT_MATCH_DAYS)..(on + RECEIPT_MATCH_DAYS))
      # A row already carrying THIS message's blob wins first: keeps a job re-run a no-op
      # even if a crash landed between the receipt attach and the processed mark.
      if @msg.media.attached?
        rerun = scope.joins(:receipt_attachment)
                     .find_by(active_storage_attachments: { blob_id: @msg.media.blob.id })
        return rerun if rerun
      end
      candidates = scope.where.missing(:receipt_attachment).order(occurred_on: :desc, id: :desc)
      return candidates.first if instrument
      rows = candidates.limit(2).to_a
      rows.size == 1 ? rows.first : nil
    end

    def self.assign_instrument(txn, instrument)
      case instrument
      when BankAccount then txn.bank_account = instrument
      when CreditCard  then txn.credit_card = instrument
      end
    end

    # Card rows follow the closing rule; everything else buckets by calendar month.
    def self.billing_month_for(instrument, occurred_on)
      instrument.is_a?(CreditCard) ? instrument.billing_month_for(occurred_on) : occurred_on.beginning_of_month
    end

    def reply(key, txn, **args) = WhatsappReply.deliver(user: @msg.user, key: key, transaction: txn, **args)

    def self.today = Time.current.in_time_zone("America/Sao_Paulo").to_date
    def today = self.class.today
  end
end
