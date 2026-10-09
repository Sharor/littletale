const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const controllerPath = "app/javascript/controllers/book_wizard_controller.js"

function storage(initial = {}) {
  const values = new Map(Object.entries(initial))
  return {
    getItem: key => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, value),
    removeItem: key => values.delete(key)
  }
}

function target() {
  return {
    hidden: false,
    scrollCalls: 0,
    attributes: {},
    classList: { toggle() {} },
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
    scrollIntoView() { this.scrollCalls += 1 },
    focus() {}
  }
}

function controllerInstance({ savedDraft, explicitCharacters = false, characterIds = [] } = {}) {
  assert.ok(fs.existsSync(controllerPath), "expected the book wizard controller to exist")
  const localStorage = storage(savedDraft ? {
    "little-stories:book-wizard:42:v1": JSON.stringify(savedDraft)
  } : {})
  const windowListeners = {}
  const context = {
    localStorage,
    window: {
      addEventListener(type, listener) { windowListeners[type] = listener },
      removeEventListener(type) { delete windowListeners[type] },
      location: { assign() {} }
    },
    document: { createElement: () => ({ type: "hidden", dataset: {} }) },
    Event: class { constructor(type) { this.type = type } }
  }
  const source = fs.readFileSync(controllerPath, "utf8")
    .replace(/import .*\n/, "class Controller {}\n")
    .replace("export default class", "globalThis.BookWizardController = class")
  vm.runInNewContext(source, context)

  const fields = [
    { name: "book[language]", type: "select-one", value: "en", options: [ { value: "en", text: "English" }, { value: "da", text: "Danish" } ] },
    { name: "book[name]", type: "text", value: "" },
    { name: "book[book_font]", type: "radio", value: "eb_garamond", checked: true, dataset: { reviewLabel: "EB Garamond" } },
    { name: "book[book_font]", type: "radio", value: "inter", checked: false, dataset: { reviewLabel: "Inter" } },
    ...characterIds.map(value => ({
      name: "book[character_ids][]", type: "hidden", value: String(value),
      dataset: { bookCharacterId: "true", reviewLabel: value === "9" ? "Mia" : "Noah" }
    }))
  ]
  const element = {
    elements: fields,
    append(field) { fields.push(field) },
    checkValidity: () => true,
    reportValidity() {},
    querySelector: selector => selector === ":invalid" ? null : null,
    querySelectorAll: selector => selector === "[data-book-character-id]" ? [] : []
  }
  const controller = new context.BookWizardController()
  const navTarget = {
    clientWidth: 300,
    scrollLeft: 0,
    scrollTo({ left }) { this.scrollLeft = left },
    getBoundingClientRect() { return { left: 0, width: this.clientWidth } }
  }
  const stepButtonTargets = [ target(), target(), target(), target(), target() ]
  stepButtonTargets.forEach((button, index) => {
    button.offsetLeft = index * 140
    button.offsetWidth = 140
    button.getBoundingClientRect = () => ({ left: index * 140, width: 140 })
  })
  Object.assign(controller, {
    element,
    stepTargets: [ target(), target(), target(), target(), target() ],
    stepButtonTargets,
    navTarget,
    previousTarget: target(), nextTarget: target(), submitTarget: target(), statusTarget: target(),
    characterReviewTarget: { textContent: "" },
    reviewTargets: [],
    userKeyValue: "42", initialStepValue: 0, errorsValue: false, explicitCharactersValue: explicitCharacters,
    allowedCharacterIdsValue: ["9", "10"],
    characterNamesValue: { "9": "Mia", "10": "Noah" }, noCharactersTextValue: "No characters selected",
    newUrlValue: "/books/new", savedTextValue: "Saved", otherTabTextValue: "Changed"
  })
  fields.forEach(field => { field.dispatchEvent = () => controller.save() })
  return { controller, fields, localStorage, windowListeners }
}

test("restores unfinished values and the active step from this user's browser draft", () => {
  const { controller, fields, localStorage } = controllerInstance({ savedDraft: {
    version: 1,
    step: 3,
    fields: { "book[name]": [ "Moon voyage" ], "book[book_font]": [ "inter" ] }
  } })

  controller.connect()

  assert.equal(fields.find(field => field.name === "book[name]").value, "Moon voyage")
  assert.equal(fields.find(field => field.value === "inter").checked, true)
  assert.equal(controller.currentStep, 3)
  assert.equal(controller.stepTargets[3].hidden, false)
  assert.equal(controller.stepTargets[0].hidden, true)
  assert.equal(controller.navTarget.scrollLeft, 340)
  const retainedDraft = JSON.parse(localStorage.getItem("little-stories:book-wizard:42:v1"))
  assert.equal(retainedDraft.step, 3)
  assert.deepEqual(retainedDraft.fields["book[name]"], ["Moon voyage"])
})

test("saves raw form values and navigation progress without submitting", () => {
  const { controller, fields, localStorage } = controllerInstance()
  controller.connect()
  fields.find(field => field.name === "book[name]").value = "Forest friends"

  controller.next({ preventDefault() {} })

  const draft = JSON.parse(localStorage.getItem("little-stories:book-wizard:42:v1"))
  assert.equal(draft.step, 1)
  assert.deepEqual(draft.fields["book[name]"], [ "Forest friends" ])
})

test("clears a draft only after a successful Turbo submission", () => {
  const { controller, localStorage } = controllerInstance()
  controller.connect()
  controller.save()

  controller.submissionEnded({ detail: { success: false } })
  assert.notEqual(localStorage.getItem("little-stories:book-wizard:42:v1"), null)

  controller.submissionEnded({ detail: {
    success: true,
    fetchResponse: { response: { url: "http://example.test/settings" } }
  } })
  assert.notEqual(localStorage.getItem("little-stories:book-wizard:42:v1"), null)

  controller.submissionEnded({ detail: {
    success: true,
    fetchResponse: { response: { url: "http://example.test/books/123" } }
  } })
  assert.equal(localStorage.getItem("little-stories:book-wizard:42:v1"), null)
})

test("prevents duplicate generation submissions and re-enables after a rejected response", () => {
  const { controller } = controllerInstance()
  controller.connect()
  controller.showStep(4)

  controller.submit({ preventDefault() { assert.fail("valid form should submit") } })
  assert.equal(controller.submitTarget.disabled, true)

  let duplicatePrevented = false
  controller.submit({ preventDefault() { duplicatePrevented = true } })
  assert.equal(duplicatePrevented, true)

  controller.submissionEnded({ detail: { success: false } })
  assert.equal(controller.submitTarget.disabled, false)
})

test("an implicit submit from an intermediate step advances without generating", () => {
  const { controller } = controllerInstance()
  controller.connect()
  let prevented = false

  controller.submit({ preventDefault() { prevented = true } })

  assert.equal(prevented, true)
  assert.equal(controller.currentStep, 1)
  assert.notEqual(controller.submitTarget.disabled, true)
})

test("recenters the active step when the viewport changes", () => {
  const { controller, windowListeners } = controllerInstance({ savedDraft: {
    version: 1,
    step: 3,
    fields: {}
  } })
  controller.connect()
  controller.navTarget.scrollLeft = 0

  windowListeners.resize()

  assert.equal(controller.navTarget.scrollLeft, 340)
})

test("restores only character ids that still belong to the ready-character set", () => {
  const { controller, fields } = controllerInstance({ savedDraft: {
    version: 1,
    step: 0,
    fields: { "book[character_ids][]": ["9", "99"] }
  } })

  controller.connect()

  assert.deepEqual(
    fields.filter(field => field.name === "book[character_ids][]").map(field => field.value),
    ["9"]
  )
  assert.equal(controller.characterReviewTarget.textContent, "Mia")
})

test("clears every saved choice when returning with a different explicit character selection", () => {
  const { controller, fields, localStorage } = controllerInstance({
    explicitCharacters: true,
    characterIds: ["10"],
    savedDraft: {
      version: 1,
      step: 3,
      fields: {
        "book[name]": ["Old adventure"],
        "book[book_font]": ["inter"],
        "book[character_ids][]": ["9"]
      }
    }
  })

  controller.connect()

  assert.equal(localStorage.getItem("little-stories:book-wizard:42:v1"), null)
  assert.equal(fields.find(field => field.name === "book[name]").value, "")
  assert.equal(fields.find(field => field.value === "eb_garamond").checked, true)
  assert.equal(controller.currentStep, 0)
})

test("keeps saved choices when the explicit character selection is unchanged", () => {
  const { controller, fields, localStorage } = controllerInstance({
    explicitCharacters: true,
    characterIds: ["10", "9"],
    savedDraft: {
      version: 1,
      step: 3,
      fields: {
        "book[name]": ["Shared adventure"],
        "book[character_ids][]": ["9", "10"]
      }
    }
  })

  controller.connect()

  assert.notEqual(localStorage.getItem("little-stories:book-wizard:42:v1"), null)
  assert.equal(fields.find(field => field.name === "book[name]").value, "Shared adventure")
  assert.equal(controller.currentStep, 3)
})
