module Notifications
  # The ONE send policy for every proactive notification (.plans/up-tier 01 §3), called
  # after the Notification row exists. Dashboard visibility is inherent — the row already
  # shows in-app; this only decides the WhatsApp push. Gates run in order and ALL fail
  # closed: toggle + consent → identity + channel → quiet hours → daily cap → atomic
  # claim → WhatsappReply.deliver.
  #
  # Phase 3 (ADR 0011 signed): the push is LIVE. The claim is fail-closed — a crash after
  # claim loses the message, never duplicates it — and every send goes through
  # WhatsappReply (logged as an outbound WhatsappMessage, rendered in the recipient's
  # locale, money pre-formatted by Ruby; NEVER raw WhatsappService.send_message).
  class Deliver
    DAILY_WA_CAP = 3                  # per-user WhatsApp pushes/day (07 D14; tunable constant)
    TIME_ZONE    = "America/Sao_Paulo"

    def self.call(notification) = new(notification).call

    def initialize(notification)
      @notification = notification
      @user         = notification.user
    end

    # true only when the push actually went out (Phase 3). Explicitly silent otherwise:
    # toggle off · no consent · unverified/no JID · sidecar down · quiet hours · over cap.
    def call
      return false unless push_allowed?
      claim_and_send
    end

    # Gates 1–4 — whether this notification may reach WhatsApp at all.
    def push_allowed?
      toggle_on? && prefs.whatsapp_consent? && channel_ready? && !quiet_hours? && under_daily_cap?
    end

    private

    def prefs = @prefs ||= @user.notification_prefs

    # Gate 1 — the per-kind toggle, resolved through the KINDS registry (never user input).
    def toggle_on?
      prefs.public_send("#{KINDS.fetch(@notification.kind).fetch(:toggle)}?")
    end

    # Gate 2 — identity + channel: verified ownership, the exact captured JID (a bare
    # phone may not reach @lid contacts), and a live sidecar. Sidecar down → dashboard-
    # only, claim NOT burned, no retry (the next sweep re-offers time-relevant items).
    def channel_ready?
      @user.phone_verified? && @user.whatsapp_jid.present? && WhatsappConnection.instance.connected?
    end

    # Gate 3 — no push inside [quiet_hours_start, quiet_hours_end) SP-time. The window may
    # wrap midnight (default 21→8); start == end ⇒ empty window, never quiet. Inside →
    # dashboard-only, not re-queued (a stale 2am push helps no one).
    def quiet_hours?
      hour, from, to = now_sp.hour, prefs.quiet_hours_start, prefs.quiet_hours_end
      from <= to ? (from...to).cover?(hour) : (hour >= from || hour < to)
    end

    # Gate 4 — per-user daily cap, counted from claims stamped today SP-time. Summaries
    # are exempt-by-scarcity (≤1/week, ≤1/month) but still counted.
    def under_daily_cap?
      Notification.where(user: @user, whatsapp_sent_at: now_sp.all_day).count < DAILY_WA_CAP
    end

    def now_sp = Time.current.in_time_zone(TIME_ZONE)

    # Gates 5–6 — the atomic fail-closed claim followed by the logged + localized send.
    # update_all on the nil-claim predicate makes the DB the referee: two concurrent
    # deliveries race, exactly one matches a row, only the winner sends. A crash after
    # claim loses the message, never duplicates it (no rollback, no retry — the next
    # sweep covers time-relevant items).
    def claim_and_send
      claimed = Notification.where(id: @notification.id, whatsapp_sent_at: nil)
                            .update_all(whatsapp_sent_at: Time.current) == 1
      return false unless claimed
      footer = intro_footer_pending?
      WhatsappReply.deliver(user: @user,
                            key: "whatsapp.replies.notifications.#{Notifications.template_key(@notification)}",
                            footer_key: ("whatsapp.replies.notifications_footer" if footer),
                            **template_args)
      mark_intro_sent! if footer
      true
    end

    # Money formatted by Ruby BEFORE interpolation, in the RECIPIENT's locale — the same
    # payload transform the dashboard banner uses (Notifications.template_args), with the
    # brl-equivalent formatter for a job context. The whole transform runs inside the
    # recipient's locale: the summary digests assemble composite lines (Summaries::Lines)
    # here, not just money.
    # Goal kinds render whole reais, same fork as the dashboard banner
    # (NotificationsHelper#notification_message); budget_*_goal stays 2-decimal.
    # goal_alert CEILs (round 3 P1: a gap top-up is never under-asked); goal_achieved FLOORs
    # ("você guardou X" is a ledger figure — never overstate it), matching the goal page party.
    def template_args
      whole  = %w[goal_alert goal_achieved].include?(@notification.kind)
      ledger = @notification.kind == "goal_achieved"
      I18n.with_locale(@user.locale) do
        Notifications.template_args(@notification) do |cents|
          cents = Money.floor_to_real(cents) if ledger   # pre-floored → the whole:true ceil is a no-op
          WhatsappReply.currency(cents, locale: @user.locale, whole: whole)
        end
      end
    end

    # The one-time opt-out courtesy (01 §2): the FIRST push a user ever gets DELIVERED
    # carries a "responda *parar*" footer; subsequent ones don't. Read-then-stamp, with
    # the stamp AFTER the send succeeds — a failed send must not burn the courtesy. The
    # per-user job serialization (the shared "proactive_notify" concurrency group) keeps
    # the read race-free; the remaining failure mode is the benign direction: a crash
    # between send and stamp repeats the footer once on the NEXT push. prefs is always
    # persisted here: consent (gate 1) is only ever true on a saved row.
    def intro_footer_pending? = prefs.wa_intro_sent_at.nil?

    # update_column (not update_all) so the cached association object is stamped too —
    # a multi-event sweep reuses the same user across Deliver calls, and the second push
    # of a first-ever sweep must not repeat the footer.
    def mark_intro_sent!
      prefs.update_column(:wa_intro_sent_at, Time.current)
    end
  end
end
