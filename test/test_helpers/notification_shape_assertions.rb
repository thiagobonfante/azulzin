# The message-format contract as assertions (.plans/up-tier 08 §9) — every proactive
# WhatsApp template must pass, in BOTH locales, or the build fails. Include in a test
# class and call assert_notification_shape on a RENDERED body (real interpolations, money
# already formatted). `type:` sets the line cap: :alert (≤3) · :suggestion (≤2) ·
# :digest (≤8, Phase 4's weekly/monthly summaries reuse this helper unchanged).
module NotificationShapeAssertions
  # 08 §3 — one glyph, one meaning; a message opens with exactly one of these.
  LEGEND_GLYPHS = %w[🔔 📄 💰 👀 ⚠️ 💙 📊 📅].freeze
  # 08 §2.3 — banned jargon, matched accent-insensitively on the rendered copy.
  BANNED_JARGON = %w[aporte provisionar comprometimento competencia mtd orcamentario].freeze
  LINE_CAPS     = { alert: 3, suggestion: 2, digest: 8 }.freeze
  EMOJI_RE      = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]/

  def assert_notification_shape(body, type: :alert, label: body)
    assert body.present?, "#{label}: renders non-empty"

    lines = body.strip.split("\n")
    cap   = LINE_CAPS.fetch(type)
    assert lines.size <= cap, "#{label}: #{lines.size} lines exceeds the #{type} cap of #{cap}"

    glyph = LEGEND_GLYPHS.find { |g| body.start_with?(g) }
    assert glyph, "#{label}: must open with exactly one legend glyph (08 §3)"

    rest   = body.delete_prefix(glyph)
    emojis = rest.scan(EMOJI_RE)
    assert emojis.empty? || (emojis == [ "💙" ] && rest.rstrip.end_with?("💙")),
           "#{label}: no emoji beyond the leading glyph except one optional closing 💙"

    assert body.match?(/\*[^*\s][^*]*\*/), "#{label}: the subject must be bolded (*…*)"
    assert body.match?(/R\$\s?\d/), "#{label}: a formatted money value must be present"
    assert body.count("?") <= 1, "#{label}: at most one call-to-action question"
    assert_not body.match?(/\d\s?%/), "#{label}: no raw percentages (08 §2.3)"

    normalized = TextMatch.normalize(body)
    BANNED_JARGON.each do |word|
      assert_not normalized.include?(word), "#{label}: banned jargon #{word.inspect} (08 §2.3)"
    end
  end
end
