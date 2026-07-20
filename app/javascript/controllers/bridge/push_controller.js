import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Native push registration (.plans/mobile/04 §3). Loads ONLY inside a shell that
// registered the "push" component (shouldLoad checks the UA's bridge-components list) —
// on the web this controller never activates and the Avisos row stays hidden.
// Two entry points: the Avisos row's explicit "Ativar" tap (OS permission prompt), and
// a silent re-register on every launch when permission is already granted (token
// rotation must never strand a device), throttled to once a day.
export default class extends BridgeComponent {
  static component = "push"
  static targets = ["row"]

  static REREGISTER_MS = 24 * 60 * 60 * 1000

  connect() {
    super.connect()
    if (this.hasRowTarget) this.rowTarget.hidden = false
    this.#silentReregister()
  }

  enable() {
    this.send("register", {}, (message) => this.#post(message.data))
  }

  #silentReregister() {
    const last = Number(localStorage.getItem("push-registered-at") || 0)
    if (Date.now() - last < this.constructor.REREGISTER_MS) return
    this.send("registerIfGranted", {}, (message) => this.#post(message.data))
  }

  async #post({ token, platform, appVersion }) {
    if (!token) return
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch("/push_devices", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ token, platform, app_version: appVersion })
    })
    if (response.ok) localStorage.setItem("push-registered-at", String(Date.now()))
  }
}
