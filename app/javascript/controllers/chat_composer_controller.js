import { Controller } from "@hotwired/stimulus"

// Chat composer (.plans/mobile/08 §4): mic capture via MediaRecorder — the recorded blob
// becomes a File on the same media input an attached receipt uses, then the form submits.
// Tap the mic to record (button turns red), tap again to stop & send.
export default class extends Controller {
  static targets = ["media", "mic", "fileName"]

  async toggleRecording() {
    if (this.recorder && this.recorder.state === "recording") {
      this.recorder.stop()
      return
    }
    let stream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      return // permission denied — the button simply does nothing
    }
    // WKWebView records AAC in mp4; Android WebView/desktop record Opus in webm.
    const mime = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/mp4"
    const chunks = []
    this.recorder = new MediaRecorder(stream, { mimeType: mime })
    this.recorder.ondataavailable = (e) => chunks.push(e.data)
    this.recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop())
      this.micTarget.classList.remove("btn-error", "text-error")
      const file = new File(chunks, mime === "audio/webm" ? "audio.webm" : "audio.m4a", { type: mime })
      const list = new DataTransfer()
      list.items.add(file)
      this.mediaTarget.files = list.files
      this.recorder = null
      this.element.requestSubmit()
    }
    this.recorder.start()
    this.micTarget.classList.add("btn-error", "text-error")
  }

  fileChosen() {
    const file = this.mediaTarget.files[0]
    this.fileNameTarget.textContent = file ? file.name : ""
  }
}
