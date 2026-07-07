module Notifications
  # The service-level WhatsApp opt-out (.plans/up-tier 01 §2): a deterministic 0-LLM
  # pre-pass in the inbound pipeline (mirrors the shipped undo pre-pass), run before any
  # extraction — a "parar" must be instant and never depend on LLM mood. v1 = GLOBAL stop
  # (whatsapp_consent off, all kinds); re-enable is in-app only, a considered action.
  #
  # Detection is full-message-intent only: the whole (normalized) message must BE the
  # stop phrase — a "parar" mid-sentence ("gastei 50 sem parar") never hijacks an expense.
  class StopCommand
    # Anchored over TextMatch.normalize (accents stripped, downcased, whitespace
    # collapsed), trailing punctuation tolerated. At least as conservative as UNDO_RE.
    STOP_RE = /\A(?:parar|stop|(?:para|parar|pare)\sde\s(?:me\s)?avisar|nao\squero\smais\s(?:os\s)?avisos?)[\s.!]*\z/

    def self.detect(text)
      STOP_RE.match?(TextMatch.normalize(text))
    end

    # Turns consent off (creating the preference row if the user never opened Avisos —
    # harmless for a never-opted-in user, who still deserves the confirmation) and
    # confirms ONCE, templated. The caller stops the pipeline for this message.
    def self.call(msg)
      msg.user.notification_prefs.update!(whatsapp_consent: false)
      WhatsappReply.deliver(user: msg.user, key: "whatsapp.replies.notifications_stopped")
    end
  end
end
