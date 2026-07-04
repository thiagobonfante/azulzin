import { Controller } from "@hotwired/stimulus"

// Masks the national phone number as (00) 00000-0000 when Brazil (+55) is selected; other
// countries just keep digits. The dial code is submitted separately (target "country") and
// the server joins the two into E.164 — so this is presentation only.
export default class extends Controller {
  static targets = ["country", "number"]

  connect() {
    this.reformat()
  }

  reformat() {
    let d = this.numberTarget.value.replace(/\D/g, "")

    if (this.countryTarget.value === "55") {
      d = d.slice(0, 11)
      let out = d
      if (d.length > 2 && d.length <= 6) out = `(${d.slice(0, 2)}) ${d.slice(2)}`
      else if (d.length > 6 && d.length <= 10) out = `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
      else if (d.length > 10) out = `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
      this.numberTarget.value = out
    } else {
      this.numberTarget.value = d.slice(0, 15)
    }
  }
}
