# Namespace + static reference data for the WhatsApp channel.
#
# INSTITUTION_ALIASES: colloquial names → COMPE code, seeded from config/institution_aliases.yml
# as a frozen constant (a table would be gold-plating for static data — see .plans/whats §6.6).
# Values are normalized (accent-stripped, downcased, whitespace-collapsed) at load so the
# Matcher can compare against an equally-normalized instrument phrase.
module Whatsapp
  # Normalize / similarity primitives live in TextMatch (shared with Categories::*);
  # these delegates keep the long-standing Whatsapp.* call sites and tests intact.
  def self.normalize(term) = TextMatch.normalize(term)
  def self.similarity(a, b) = TextMatch.similarity(a, b)
  def self.trigrams(str) = TextMatch.trigrams(str)

  INSTITUTION_ALIASES =
    YAML.safe_load_file(Rails.root.join("config/institution_aliases.yml"))
        .transform_values { |aliases| aliases.map { |a| normalize(a) }.uniq.freeze }
        .freeze

  # Aliases of this length or shorter must match as a whole token only, never fuzzily
  # (kills "bb"/"nu"/"mp"/"pan" noise). Used by the Matcher's term_sim tiering.
  SHORT_ALIAS_MAX = 4

  def self.aliases_for(code) = INSTITUTION_ALIASES.fetch(code.to_s, [].freeze)

  # Shared secret between Rails and the sidecar (both directions). Credentials first, ENV
  # fallback (the sidecar itself is configured via ENV, so this keeps the two symmetric and
  # makes tests/local dev easy).
  def self.service_token
    Rails.application.credentials.dig(:whatsapp, :service_token).presence || ENV["WHATSAPP_SERVICE_TOKEN"].presence
  end
end
