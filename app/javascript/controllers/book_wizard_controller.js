import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "stepButton", "nav", "previous", "next", "submit", "status", "review", "characterReview"]
  static values = {
    userKey: String,
    initialStep: Number,
    errors: Boolean,
    explicitCharacters: Boolean,
    allowedCharacterIds: Array,
    characterNames: Object,
    noCharactersText: String,
    newUrl: String,
    savedText: String,
    otherTabText: String
  }

  connect() {
    this.storageKey = `little-stories:book-wizard:${this.userKeyValue}:v1`
    this.boundStorageChanged = this.storageChanged.bind(this)
    this.boundViewportChanged = this.viewportChanged.bind(this)
    this.submitting = false
    window.addEventListener("storage", this.boundStorageChanged)
    window.addEventListener("resize", this.boundViewportChanged)

    let restoredStep = null
    this.restoringDraft = true
    try {
      restoredStep = this.errorsValue ? null : this.restoreDraft()
    } finally {
      this.restoringDraft = false
    }
    const startingStep = restoredStep === null ? this.initialStepValue : restoredStep
    this.showStep(startingStep)
    this.updateReview()
  }

  disconnect() {
    window.removeEventListener("storage", this.boundStorageChanged)
    window.removeEventListener("resize", this.boundViewportChanged)
  }

  next(event) {
    event?.preventDefault()
    this.save()
    this.showStep(this.currentStep + 1, { focus: true, persist: true })
  }

  previous(event) {
    event?.preventDefault()
    this.save()
    this.showStep(this.currentStep - 1, { focus: true, persist: true })
  }

  goTo(event) {
    event.preventDefault()
    this.save()
    this.showStep(Number(event.currentTarget.dataset.stepIndex), { focus: true, persist: true })
  }

  showStep(requestedStep, { focus = false, persist = false } = {}) {
    const lastStep = this.stepTargets.length - 1
    const step = Math.max(0, Math.min(Number(requestedStep) || 0, lastStep))
    this.currentStep = step

    this.stepTargets.forEach((target, index) => { target.hidden = index !== step })
    this.stepButtonTargets.forEach((button, index) => {
      if (index === step) button.setAttribute("aria-current", "step")
      else button.removeAttribute("aria-current")
      button.classList.toggle("is-current", index === step)
    })

    this.previousTarget.hidden = step === 0
    this.nextTarget.hidden = step === lastStep
    this.submitTarget.hidden = step !== lastStep
    this.centerStepButton(this.stepButtonTargets[step])
    this.updateReview()
    if (persist) this.save()

    if (focus) {
      const heading = this.stepTargets[step].querySelector?.("h2")
      if (heading) {
        heading.setAttribute("tabindex", "-1")
        heading.focus()
      }
    }
  }

  centerStepButton(button) {
    const navRect = this.navTarget.getBoundingClientRect()
    const buttonRect = button.getBoundingClientRect()
    const left = this.navTarget.scrollLeft + buttonRect.left - navRect.left - (navRect.width - buttonRect.width) / 2
    this.navTarget.scrollTo({ left: Math.max(0, left), behavior: "auto" })
  }

  viewportChanged() {
    this.centerStepButton(this.stepButtonTargets[this.currentStep])
  }

  save() {
    if (this.restoringDraft) return

    const draft = { version: 1, step: this.currentStep || 0, fields: this.serializedFields() }
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(draft))
      this.statusTarget.textContent = this.savedTextValue
    } catch (_error) {
      this.statusTarget.textContent = ""
    }
    this.updateReview()
  }

  serializedFields() {
    const fields = {}
    Array.from(this.element.elements).forEach(field => {
      if (!field.name || field.disabled || ["submit", "button", "file"].includes(field.type)) return
      if (["authenticity_token", "commit", "_method"].includes(field.name)) return
      if (["radio", "checkbox"].includes(field.type) && !field.checked) return

      fields[field.name] ||= []
      fields[field.name].push(field.value)
    })
    return fields
  }

  restoreDraft() {
    try {
      const rawDraft = localStorage.getItem(this.storageKey)
      if (!rawDraft) return null

      const draft = JSON.parse(rawDraft)
      if (draft.version !== 1 || !draft.fields || typeof draft.fields !== "object") return null
      if (this.explicitCharactersValue && !this.draftCharactersMatch(draft.fields)) {
        localStorage.removeItem(this.storageKey)
        return null
      }
      this.restoreFields(draft.fields)
      return Number.isInteger(draft.step) ? draft.step : 0
    } catch (_error) {
      return null
    }
  }

  draftCharactersMatch(fields) {
    const characterName = "book[character_ids][]"
    const savedIds = this.normalizedCharacterIds(fields[characterName])
    const selectedIds = this.normalizedCharacterIds(
      Array.from(this.element.elements)
        .filter(field => field.name === characterName)
        .map(field => field.value)
    )
    return savedIds.length === selectedIds.length && savedIds.every((id, index) => id === selectedIds[index])
  }

  normalizedCharacterIds(values) {
    const ids = Array.isArray(values) ? values : values == null ? [] : [values]
    return [...new Set(ids.map(value => String(value).trim()).filter(Boolean))].sort()
  }

  restoreFields(fields) {
    const characterName = "book[character_ids][]"
    if (!this.explicitCharactersValue && Array.isArray(fields[characterName])) {
      this.element.querySelectorAll("[data-book-character-id]").forEach(field => field.remove())
      fields[characterName].filter(value => this.allowedCharacterIdsValue.includes(String(value))).forEach(value => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = characterName
        input.value = value
        input.dataset.bookCharacterId = "true"
        input.dataset.reviewLabel = this.characterNamesValue[String(value)]
        this.element.append(input)
      })
    }

    Object.entries(fields).forEach(([name, values]) => {
      if (name === characterName) return
      const controls = Array.from(this.element.elements).filter(field => field.name === name)
      controls.forEach((field, index) => {
        if (["radio", "checkbox"].includes(field.type)) field.checked = values.includes(field.value)
        else if (index === 0) field.value = values[0] ?? ""
      })
      controls.filter(field => field.checked && field.dispatchEvent)
        .forEach(field => field.dispatchEvent(new Event("change", { bubbles: true })))
    })
  }

  submit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    this.save()
    if (this.currentStep !== this.stepTargets.length - 1) {
      event.preventDefault()
      this.showStep(this.currentStep + 1, { focus: true, persist: true })
      return
    }

    if (this.element.checkValidity()) {
      this.submitting = true
      this.submitTarget.disabled = true
      return
    }

    event.preventDefault()
    const invalidField = this.element.querySelector(":invalid")
    const invalidStep = invalidField?.closest?.("[data-book-wizard-target='step']")
    if (invalidStep) this.showStep(this.stepTargets.indexOf(invalidStep), { focus: true, persist: true })
    this.element.reportValidity()
  }

  submissionEnded(event) {
    this.submitting = false
    this.submitTarget.disabled = false
    if (!event.detail.success || !this.createdBookDestination(event.detail.fetchResponse?.response?.url)) return
    try { localStorage.removeItem(this.storageKey) } catch (_error) { /* Storage may be unavailable. */ }
  }

  createdBookDestination(url) {
    const path = String(url || "").replace(/^https?:\/\/[^/]+/, "").split(/[?#]/)[0]
    return /^\/books\/\d+(?:\.html)?$/.test(path) || /^\/books\/\d+\/parent_approval$/.test(path)
  }

  reset(event) {
    event.preventDefault()
    try { localStorage.removeItem(this.storageKey) } catch (_error) { /* Storage may be unavailable. */ }
    window.location.assign(this.newUrlValue)
  }

  storageChanged(event) {
    if (event.key === this.storageKey) this.statusTarget.textContent = this.otherTabTextValue
  }

  updateReview() {
    if (!this.reviewTargets) return
    this.reviewTargets.forEach(target => {
      const name = `book[${target.dataset.reviewField}]`
      const fields = Array.from(this.element.elements).filter(field => field.name === name)
      const selected = fields.find(field => !["radio", "checkbox"].includes(field.type) || field.checked)
      let value = selected?.dataset?.reviewLabel || selected?.value || ""
      if (selected?.options) value = selected.options[selected.selectedIndex]?.text || value
      target.textContent = value.trim() || "—"
    })

    const characterNames = Array.from(this.element.elements)
      .filter(field => field.name === "book[character_ids][]")
      .map(field => field.dataset?.reviewLabel || this.characterNamesValue[String(field.value)])
      .filter(Boolean)
    this.characterReviewTarget.textContent = [...new Set(characterNames)].join(", ") || this.noCharactersTextValue
  }
}
