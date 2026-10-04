import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "dialog", "pin", "status"]
  static values = {
    initialEnabled: Boolean,
    onLabel: String,
    offLabel: String
  }

  connect() {
    this.syncAppearance()
  }

  toggle() {
    this.syncAppearance()

    if (!this.hasDialogTarget) return
    if (this.toggleTarget.checked === this.initialEnabledValue) {
      this.pinTarget.value = ""
      this.pinTarget.required = false
      return
    }

    this.pinTarget.required = true
    this.dialogTarget.showModal()
    this.pinTarget.focus()
  }

  confirm(event) {
    event.preventDefault()
    if (!this.pinTarget.reportValidity()) return

    const form = this.element.closest("form")
    if (!form) return

    this.dialogTarget.close()
    form.requestSubmit()
  }

  cancel(event) {
    event.preventDefault()
    this.restoreInitialState()
  }

  closeOnBackdrop(event) {
    if (event.target !== this.dialogTarget) return

    const bounds = this.dialogTarget.getBoundingClientRect()
    const inside = event.clientX >= bounds.left && event.clientX <= bounds.right &&
      event.clientY >= bounds.top && event.clientY <= bounds.bottom

    if (!inside) this.restoreInitialState()
  }

  restoreInitialState() {
    this.toggleTarget.checked = this.initialEnabledValue
    this.pinTarget.value = ""
    this.pinTarget.required = false
    this.dialogTarget.close()
    this.syncAppearance()
    this.toggleTarget.focus()
  }

  syncAppearance() {
    const enabled = this.toggleTarget.checked
    this.element.classList.toggle("parent-restricted-setting--disabled", !enabled)
    this.statusTarget.textContent = enabled ? this.onLabelValue : this.offLabelValue
  }
}
