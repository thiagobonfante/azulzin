import { Controller } from "@hotwired/stimulus"

// Polls the #import_status Turbo Frame every 2s while any import is still non-terminal, then
// stops. No ActionCable (D9): a seconds-long wait doesn't warrant a persistent connection.
// The DOM is the source of truth — each row carries data-import-active; when none remain
// active the interval clears. Reload-safe (derived, never client state).
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 } }

  connect() {
    this.frame = this.element.querySelector("turbo-frame")
    this.element.addEventListener("turbo:frame-load", this.onFrameLoad)
    if (this.hasActiveRows()) this.start()
  }

  disconnect() {
    this.stop()
    this.element.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  onFrameLoad = () => {
    if (this.hasActiveRows()) this.start()
    else this.stop()
  }

  hasActiveRows() {
    return this.element.querySelector('[data-import-active="true"]') !== null
  }

  start() {
    if (this.timer) return
    this.timer = setInterval(() => this.frame && this.frame.reload(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return
    clearInterval(this.timer)
    this.timer = null
  }
}
