import { Controller } from "@hotwired/stimulus"

// Generic "add another row": clones the <template> into the container. Stimulus picks up
// controllers inside the inserted HTML (money-mask etc.) on its own.
export default class extends Controller {
  static targets = ["template", "container"]

  add(event) {
    event.preventDefault()
    this.containerTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
  }
}
