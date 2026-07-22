import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Native SSO (.plans/mobile/10). Google blocks OAuth inside webviews (403
// disallowed_useragent), so the shell's SDK produces an ID token and this controller
// POSTs it to /auth/:provider/token — the webview making the POST itself is what lands
// the session cookie in it. Buttons render hidden; only a shell that registered the
// "sign-in" component reveals them (shouldLoad), so the web and old builds keep
// email/password untouched.
export default class extends BridgeComponent {
  static component = "sign-in"
  static targets = ["button"]

  connect() {
    super.connect()
    this.buttonTargets.forEach((el) => (el.hidden = false))
  }

  start(event) {
    const provider = event.params.provider
    this.send("signIn", { provider }, (message) => {
      // Cancelled/failed natively → no data, stay put (the native layer showed any UI).
      if (message.data?.idToken) this.#submit(provider, message.data.idToken)
    })
  }

  // A real <form> POST (not fetch): Turbo drives it, so the server redirect + flash
  // behave exactly like the password form, and `replace` keeps the dead sign-in
  // screen out of the native tab stack.
  #submit(provider, idToken) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = `/auth/${provider}/token`
    form.dataset.turboAction = "replace"
    for (const [name, value] of [
      ["id_token", idToken],
      ["authenticity_token", document.querySelector('meta[name="csrf-token"]')?.content]
    ]) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }
    document.body.appendChild(form)
    form.requestSubmit()
  }
}
