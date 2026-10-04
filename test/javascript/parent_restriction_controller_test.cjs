const assert = require("node:assert/strict")
const fs = require("node:fs")
const test = require("node:test")
const vm = require("node:vm")

function controllerClass() {
  const path = "app/javascript/controllers/parent_restriction_controller.js"
  const source = fs.readFileSync(path, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class", "class ParentRestrictionController")
    .concat("\nmodule.exports = ParentRestrictionController\n")
  const sandbox = { module: { exports: {} } }

  vm.runInNewContext(source, sandbox)
  return sandbox.module.exports
}

test("confirm explicitly submits the profile form after validating the pin", () => {
  const ParentRestrictionController = controllerClass()
  let prevented = false
  let submitted = false
  let closed = false
  const form = { requestSubmit: () => { submitted = true } }
  const controller = {
    pinTarget: { reportValidity: () => true },
    dialogTarget: { close: () => { closed = true } },
    element: { closest: selector => selector === "form" ? form : null }
  }

  ParentRestrictionController.prototype.confirm.call(controller, {
    preventDefault: () => { prevented = true }
  })

  assert.equal(prevented, true)
  assert.equal(closed, true)
  assert.equal(submitted, true)
})

test("confirm leaves the dialog open when the pin is invalid", () => {
  const ParentRestrictionController = controllerClass()
  let prevented = false
  let submitted = false
  let closed = false
  const controller = {
    pinTarget: { reportValidity: () => false },
    dialogTarget: { close: () => { closed = true } },
    element: { closest: () => ({ requestSubmit: () => { submitted = true } }) }
  }

  ParentRestrictionController.prototype.confirm.call(controller, {
    preventDefault: () => { prevented = true }
  })

  assert.equal(prevented, true)
  assert.equal(closed, false)
  assert.equal(submitted, false)
})
