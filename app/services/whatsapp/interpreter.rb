module Whatsapp
  # The one structural change to the pipeline (07 §2): a thin intent layer over the shipped
  # skeleton. A deterministic undo pre-pass (0 LLM calls) runs first; otherwise one unified
  # extraction call classifies the intent and a dispatch table routes to a per-intent handler
  # shaped exactly like the existing Decider. Receipts never reach here (job routes images to
  # ReceiptExtractor). Regression-free: an `expense` intent runs the untouched Decider.
  class Interpreter
    # Undo must never depend on LLM mood — a frozen regex catches it for free.
    UNDO_RE = /\A(apaga|cancela|desfaz|desfazer|remove|tira|exclui)( (o|a|esse|essa|isso|ultim\w+|lancamento|gasto|compra))*\z|errei|foi engano/

    # Mutating non-expense intents don't execute their verb below this intent-classification floor.
    MUTATING = %w[income transfer installment_purchase pay_commitment edit_last undo_last move_bill].freeze
    INTENT_FLOOR = 0.75

    def initialize(msg, text)
      @msg  = msg
      @text = text.to_s
    end

    def call
      return UndoHandler.new(@msg).call if UNDO_RE.match?(Whatsapp.normalize(@text)) # 0 LLM calls

      extraction = Whatsapp::Extractor.from_text(@msg.user, @text, modality: @msg.type_audio? ? "audio" : "text")
      return low_confidence_fallback(extraction) if gated?(extraction)
      dispatch(extraction)
    end

    private

    def gated?(extraction)
      MUTATING.include?(extraction.intent) && extraction.intent_confidence < INTENT_FLOOR
    end

    def dispatch(extraction)
      case extraction.intent
      when "income"               then IncomeDecider.new(@msg, extraction).call
      when "transfer"             then TransferDecider.new(@msg, extraction).call
      when "installment_purchase" then InstallmentDecider.new(@msg, extraction).call
      when "pay_commitment"       then PayCommitmentDecider.new(@msg, extraction).call
      when "edit_last"            then EditLastHandler.new(@msg, extraction).call
      when "undo_last"            then UndoHandler.new(@msg).call
      when "query"                then QueryAnswerer.new(@msg, extraction).call
      when "expense"              then expense(extraction)
      else fallback(extraction)
      end
    end

    # Expense: the existing Decider, byte-for-byte unchanged (regression-free).
    def expense(extraction)
      match      = Whatsapp::Matcher.new(@msg.user, extraction).call
      confidence = Whatsapp::Confidence.new(extraction)
      Whatsapp::Decider.new(@msg, extraction, match, confidence).call
    end

    # A misclassified mutating intent with an amount parks a pending_review expense stub (fixable
    # in the hub tray); without an amount it gets the help menu. Never fires the verb.
    def low_confidence_fallback(extraction)
      return WhatsappReply.deliver(user: @msg.user, key: "whatsapp.replies.help") unless extraction.amount_present?
      park(extraction)
    end

    def fallback(extraction) # intent "other"
      return expense(extraction) if extraction.amount_present?
      WhatsappReply.deliver(user: @msg.user, key: "whatsapp.replies.help")
    end

    def park(extraction)
      today = Time.current.in_time_zone("America/Sao_Paulo").to_date
      txn = Transaction.find_or_create_by!(source_message_id: @msg.wa_message_id) do |t|
        t.user = @msg.user
        t.whatsapp_message = @msg
        t.amount_cents = extraction.amount_cents
        t.merchant = extraction.merchant
        t.occurred_on = extraction.occurred_on || today
        t.billing_month = (extraction.occurred_on || today).beginning_of_month
        t.status = "pending_review"
        t.source = extraction.source
        t.extraction = extraction.to_h.compact
      end
      WhatsappReply.deliver(user: @msg.user, key: "whatsapp.replies.parked", transaction: txn)
      txn
    end
  end
end
