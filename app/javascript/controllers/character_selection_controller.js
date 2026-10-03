import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "label"]
  static values = {
    withCharacters: String,
    withoutCharacters: String
  }

  connect() {
    this.update()
  }

  update() {
    const hasCharacters = this.checkboxTargets.some(checkbox => checkbox.checked)
    this.labelTarget.textContent = hasCharacters ? this.withCharactersValue : this.withoutCharactersValue
  }
}
