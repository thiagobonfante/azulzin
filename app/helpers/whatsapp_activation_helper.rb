module WhatsappActivationHelper
  # The commercial WhatsApp number formatted for humans, or nil when it isn't known yet.
  # Prefers the live sidecar session's number, falling back to a configured display number.
  def whatsapp_display_number
    raw = WhatsappConnection.instance.wa_id.presence || ENV["WHATSAPP_DISPLAY_NUMBER"].presence
    format_whatsapp_number(raw)
  end

  # "554588115410" → "+55 (45) 8811-5410". Brazilian shape: 55 + 2-digit DDD + an 8- or
  # 9-digit local number (12 or 13 digits total). Anything else degrades to "+<digits>".
  def format_whatsapp_number(raw)
    digits = raw.to_s.gsub(/\D/, "")
    return if digits.blank?

    if (m = digits.match(/\A(\d{2})(\d{2})(\d{4,5})(\d{4})\z/))
      country, ddd, prefix, suffix = m.captures
      "+#{country} (#{ddd}) #{prefix}-#{suffix}"
    else
      "+#{digits}"
    end
  end
end
