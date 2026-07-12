# Sidecar → Rails webhook. Bare API controller (no CSRF, no Authentication, no locale
# around_action, no allow_browser). Authenticates the sidecar with a shared bearer token,
# ALWAYS returns 200 fast, and does the AI work in a background job. See .plans/whats §3.2.
module Api
  module Whatsapp
    class WebhooksController < ActionController::API
      before_action :authenticate_sidecar!

      def create
        case params[:event]
        when "qr_code"          then connection.update_qr!(params.dig(:data, :qr_data_url))
        when "connected"        then connection.mark_connected!(params[:data]&.to_unsafe_h)
        when "authenticated"    then connection.update!(status: "authenticated")
        when "disconnected"     then connection.mark_disconnected!(params.dig(:data, :reason))
        when "auth_failed"      then connection.mark_auth_failed!(params.dig(:data, :error))
        when "logged_out"       then connection.mark_logged_out!
        when "message_received" then handle_message_received(params[:data])
        else Rails.logger.warn("Unknown WhatsApp event: #{params[:event]}")
        end
        head :ok   # ALWAYS 200 — never make the sidecar retry on app-logic errors
      end

      private

      def connection = WhatsappConnection.instance

      def authenticate_sidecar!
        token    = request.headers["Authorization"].to_s.split(" ").last
        expected = ::Whatsapp.service_token
        head :unauthorized unless expected.present? &&
          ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected.to_s)
      end

      def handle_message_received(data)
        data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
        jid  = data["from"]
        user = User.verified_for_wa(jid)

        # Unknown/unverified sender: short-circuit BEFORE persisting media or enqueuing
        # (Review P1-6). Try the verification handshake first, else a rate-limited reply.
        return handle_unverified_sender(jid, data) if user.nil?

        user.refresh_whatsapp_jid!(jid)   # keep the outbound reply address current (@lid/@c.us)

        # Sidecar skipped an oversized attachment (heap guard). Nothing to process — just ask
        # the user to resend a smaller file, in their language. No message stored, no job.
        return reply_media_too_large(user, jid) if data["media_too_large"]

        msg = WhatsappMessage.find_or_create_by!(wa_message_id: data["message_id_serialized"]) do |m|
          m.direction    = "inbound"
          m.chat_id      = jid
          m.message_type = map_type(data["type"])
          m.body         = data["body"]
          m.status       = "received"
          m.user         = user
          m.account      = user.account   # D6: stamp tenancy at the edge
        end
        # Capture "newly created" BEFORE attach_media — attaching media re-saves the record,
        # which flips previously_new_record? to false and would skip the enqueue for every
        # audio/receipt message.
        newly_created = msg.previously_new_record?
        attach_media(msg, data["media"]) if data["media"].present? && !msg.media.attached?
        ProcessInboundWhatsappJob.perform_later(msg.id) if newly_created
      rescue ActiveRecord::RecordNotUnique
        # redelivered webhook — already have it, no-op (still 200 in #create)
      end

      # A guessed AZUL-XXXX now binds into a FAMILY tenant (read/write over shared money), and
      # pending codes are outstanding more often (each new member holds one). So cap code-shaped
      # guesses per JID before the scan, and turn the silent double-bind into a localized reply.
      CODE_ATTEMPT_CAP = 10   # per JID per day; codes are 32^4 ≈ 1.05M → brute force is hopeless (§8.1)
      CODE_RE = /AZUL-[A-Z0-9]{4}/i

      def handle_unverified_sender(jid, data)
        return if code_attempt_over_cap?(jid, data["body"])   # §8.1 — over the cap: ignore silently
        if (u = User.awaiting_whatsapp_verification(data["body"]))
          begin
            u.verify_whatsapp!(jid)
            send_wa_reply(jid, u.locale, "whatsapp.replies.verified")
          rescue ActiveRecord::RecordNotUnique
            # §8.2: this phone is already bound to another user — one phone = one user, absolute.
            send_wa_reply(jid, u.locale, "whatsapp.replies.phone_already_linked")
          end
        elsif CODE_RE.match?(data["body"].to_s)
          reply_invalid_code(jid)
        else
          UnknownSenderReply.throttle(jid)
        end
      end

      # Wrong code under the cap: someone mid-handshake deserves feedback, not the 6h throttled
      # silence (the daily cap above still swallows brute force). Sender digits matching a
      # registered phone → "código inválido" in their locale; unknown number → sign-up nudge.
      def reply_invalid_code(jid)
        owner = User.where(phone: User.wa_id_candidates(jid)).order(:id).first
        if owner
          send_wa_reply(jid, owner.locale, "whatsapp.replies.invalid_code")
        else
          send_wa_reply(jid, I18n.default_locale, "whatsapp.replies.register_first")
        end
      end

      # Count only code-SHAPED attempts (a real user's expense text is never capped here — it
      # falls through to the unknown-sender throttle). Read-modify-write is fine for a heuristic;
      # under the test null_store it is a no-op (never caps), correct in prod (memory/redis).
      def code_attempt_over_cap?(jid, body)
        return false unless CODE_RE.match?(body.to_s)
        key   = "wa:code_attempts:#{jid.to_s.gsub(/\D/, '')}:#{Date.current}"
        count = (Rails.cache.read(key) || 0) + 1
        Rails.cache.write(key, count, expires_in: 1.day)
        count > CODE_ATTEMPT_CAP
      end

      def send_wa_reply(jid, locale, key)
        body = I18n.with_locale(locale) { I18n.t(key) }
        WhatsappService.send_message(jid, body)
      end

      def reply_media_too_large(user, jid)
        body = I18n.with_locale(user.locale) { I18n.t("whatsapp.replies.media_too_large") }
        WhatsappService.send_message(jid, body)
      end

      def map_type(type)
        case type
        when "image", "picture", "photo" then "image"
        when "audio", "ptt", "voice"     then "audio"
        when "document"                  then "document"
        else "text"
        end
      end

      def attach_media(msg, media)
        return if msg.media.attached?
        bytes = Base64.decode64(media["data"].to_s)
        ext = { %r{image/jpeg} => ".jpg", %r{image/png} => ".png", %r{audio/ogg} => ".ogg",
                %r{audio/mpeg} => ".mp3", %r{application/pdf} => ".pdf" }
                .find { |re, _| media["mimetype"].to_s =~ re }&.last.to_s
        filename = media["filename"].presence || "media_#{msg.id}#{ext}"
        msg.media.attach(io: StringIO.new(bytes), filename: filename, content_type: media["mimetype"])
      rescue StandardError => e
        Rails.logger.error("WA media attach failed: #{e.message}")   # swallow — never fail the webhook
      end
    end
  end
end
