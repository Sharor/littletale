import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.showModal()
  }

  close(event) {
    event.preventDefault()
    this.element.close()
    this.element.closest("turbo-frame").replaceChildren()
  }
}
