module Notifications
  # The ONE send policy for every proactive notification (.plans/up-tier 01 §3), called
  # after the Notification row exists. Dashboard visibility is inherent — the row already
  # shows in-app; this only decides the WhatsApp push. Gates run in order and ALL fail
  # closed: toggle + consent → identity + channel → quiet hours → daily cap → atomic
  # claim → WhatsappReply.deliver.
  #
  # Phase 0 (dashboard-only soak, ADR 0011): claim_and_send is deliberately inert — it
  # neither claims nor sends, so whatsapp_sent_at is never burned while no push exists.
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

    # Gates 5–6 — Phase 3 fills in THIS method and nothing else: the atomic fail-closed
    # claim (only the winner sends; a crash after claim loses the message, never
    # duplicates it) followed by the logged + localized send:
    #
    #   claimed = Notification.where(id: @notification.id, whatsapp_sent_at: nil)
    #                         .update_all(whatsapp_sent_at: Time.current) == 1
    #   return false unless claimed
    #   WhatsappReply.deliver(user: @user,
    #                         key: "whatsapp.replies.notifications.#{@notification.kind}",
    #                         **payload_args)
    #
    # Until then it is inert: no claim is taken and nothing is sent — the dashboard-only
    # soak required by ADR 0011.
    def claim_and_send
      false
    end
  end
end
