import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Live WhatsApp connection panel. Subscribes to BOTH admin channels through the shared
// ActionCable consumer:
//   WhatsappConnectionChannel     — swaps the QR <img> live on "qr_code"; reloads on
//                                   connected/disconnected/auth_failed so the server
//                                   re-renders the authoritative state.
//   WhatsappServiceStatusChannel  — flips the sidecar up/down badge in place (labels come
//                                   from the server via values, so no strings live in JS).
// See 07 §7.5.
export default class extends Controller {
  static targets = ["display", "serviceBadge"]
  static values = { upLabel: String, downLabel: String }

  connect() {
    this.connectionSub = consumer.subscriptions.create("WhatsappConnectionChannel", {
      received: (data) => this.handleConnectionUpdate(data)
    })
    this.statusSub = consumer.subscriptions.create("WhatsappServiceStatusChannel", {
      received: (data) => this.handleServiceStatus(data)
    })
  }

  disconnect() {
    this.connectionSub?.unsubscribe()
    this.statusSub?.unsubscribe()
  }

  handleConnectionUpdate(data) {
    switch (data.type) {
      case "qr_code":
        this.swapQr(data.qr_data_url)
        break
      case "connected":
      case "disconnected":
      case "auth_failed":
      case "logged_out":
        window.location.reload()
        break
    }
  }

  handleServiceStatus(data) {
    if (!this.hasServiceBadgeTarget) return
    this.serviceBadgeTarget.textContent = data.up ? this.upLabelValue : this.downLabelValue
    this.serviceBadgeTarget.classList.toggle("badge-success", !!data.up)
    this.serviceBadgeTarget.classList.toggle("badge-error", !data.up)
  }

  swapQr(dataUrl) {
    if (!this.hasDisplayTarget || !dataUrl) return
    let img = this.displayTarget.querySelector("img")
    if (!img) {
      img = document.createElement("img")
      img.alt = ""
      img.className = "h-56 w-56 rounded-lg"
      this.displayTarget.replaceChildren(img)
    }
    img.src = dataUrl
  }
}
