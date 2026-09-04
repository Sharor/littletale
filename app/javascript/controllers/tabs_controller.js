import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "content"]
  static values = {
    startTab: String
  }

  connect() {
    const defaultTab = this.startTabValue || "human"
    this.showTab(defaultTab)
  }

  switch(event) {
    const name = event.currentTarget.dataset.tabName
    this.showTab(name)
  }

  showTab(name) {
    this.tabTargets.forEach(el => {
      const active = el.dataset.tabName === name
      el.dataset.active = active
    })

    this.contentTargets.forEach(el => {
      el.classList.toggle("hidden", el.dataset.tabName !== name)
    })
  }
}
