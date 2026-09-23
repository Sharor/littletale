import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["language", "message", "preview"]
  static values = { en: String, da: String }

  connect() {
    this.customized = ![this.enValue, this.daValue].includes(this.messageTarget.value)
  }

  changeLanguage() {
    if (!this.customized) {
      this.messageTarget.value = this[`${this.languageTarget.value}Value`]
    }
    this.updatePreview()
  }

  markCustomized() {
    this.customized = true
    this.updatePreview()
  }

  updatePreview() {
    this.previewTarget.textContent = this.messageTarget.value
  }
}
