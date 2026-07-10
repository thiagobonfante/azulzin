require "test_helpers/e2e/pipeline_case"

# I18N-01 — the locale switch endpoint (locales#update, a zero-coverage endpoint) + the launch
# pin. The app currently PINS the rendered locale to pt-BR in code (ApplicationController#
# resolve_locale returns I18n.default_locale, ignoring param/session/user/Accept-Language — the
# temporary prod gate). So the switch endpoint runs and redirects, but the rendered money stays
# pt-BR regardless. The en-US format flip + golden matrix stay deferred until the pin lifts.
#
# NOTE (vetoable): spec 05 §8 expects the switch to flip UI + money ("prod pin is config, not
# code path"). It IS a code path — resolve_locale is hardcoded — so the flip is untestable
# today. This pins the endpoint's real behavior; discrepancy recorded in 07-coverage-audit.md.
class E2E::WebI18nTest < E2E::PipelineCase
  PT_MONEY = /R\$\s?\d{1,3}(\.\d{3})*,\d{2}/   # R$ 1.234,56

  test "locale switch endpoint runs + whitelists; rendering stays pinned to pt-BR" do
    s = E2E::Scenario.build(:history_calibrated)
    sign_in_as s.owner

    get dashboard_path
    assert_response :success
    assert_match PT_MONEY, response.body, "pt-BR money renders R$ 1.234,56"
    assert_includes response.body, "R$", "BRL symbol, never a bare $"

    patch locale_path, params: { locale: "en-US" }   # a supported locale
    assert_response :redirect

    get dashboard_path
    assert_match PT_MONEY, response.body,
                 "the launch pin holds — resolve_locale ignores the switch, money stays pt-BR"

    patch locale_path, params: { locale: "fr-FR" }   # unsupported → whitelisted out, no error
    assert_response :redirect
  end
end
