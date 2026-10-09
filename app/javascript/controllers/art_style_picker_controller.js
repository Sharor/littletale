import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "name"]

  connect() {
    const selected = this.element.querySelector("input[type='radio']:checked")
    if (selected) this.updatePreview(selected)
  }

  select(event) {
    this.updatePreview(event.currentTarget)
  }

  updatePreview(option) {
    this.previewTarget.src = option.dataset.preview
    this.previewTarget.alt = option.dataset.alt
    this.nameTarget.textContent = option.dataset.name
  }
}
