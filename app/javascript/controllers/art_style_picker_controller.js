import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "name"]

  select(event) {
    const option = event.currentTarget
    this.previewTarget.src = option.dataset.preview
    this.previewTarget.alt = option.dataset.alt
    this.nameTarget.textContent = option.dataset.name
  }
}
