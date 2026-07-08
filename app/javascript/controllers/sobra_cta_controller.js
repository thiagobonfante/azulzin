import { Controller } from "@hotwired/stimulus"

// Hero sobra CTA: hovering the blue number grows it (CSS) and teases a rotating catchphrase;
// clicking opens the save-money modal. Starts at a random phrase, then cycles so a curious
// hoverer never sees the same line twice in a row.
export default class extends Controller {
  static targets = ["phrase", "dialog"]
  static values = { phrases: Array }

  tease() {
    if (!this.phrasesValue.length || !this.hasPhraseTarget) return
    this.index = this.index === undefined
      ? Math.floor(Math.random() * this.phrasesValue.length)
      : (this.index + 1) % this.phrasesValue.length
    this.phraseTarget.textContent = this.phrasesValue[this.index]
    this.phraseTarget.classList.remove("opacity-0")
  }

  untease() {
    if (this.hasPhraseTarget) this.phraseTarget.classList.add("opacity-0")
  }

  open() {
    if (this.hasDialogTarget) this.dialogTarget.showModal()
  }
}
