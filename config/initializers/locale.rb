# UI-visible locales (narrower than config.i18n.available_locales, which also carries
# the internal :en fallback base). Drives locale whitelisting and the language switcher.
# See docs/i18n.md and ADR 0006.
Rails.application.config.x.supported_locales = {
  "pt-BR" => "Português (Brasil)",
  "en-US" => "English (US)"
}
