import { Controller } from "@hotwired/stimulus"

// Resets a form after a SUCCESSFUL Turbo submit. Keeping the form mounted (instead of
// replacing it via a Turbo Stream) means the Stimulus controllers inside it — e.g. the
// institution picker — never have to reconnect, which is what broke adding a 2nd item.
export default class extends Controller {
  reset(event) {
    if (event.detail?.success) this.element.reset()
  }
}
