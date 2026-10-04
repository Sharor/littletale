const assert = require("node:assert/strict")
const fs = require("node:fs")
const test = require("node:test")
const vm = require("node:vm")

function controllerClass() {
  const path = "app/javascript/controllers/confirmation_dialog_controller.js"
  const source = fs.readFileSync(path, "utf8")
    .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
    .replace("export default class", "class ConfirmationDialogController")
    .concat("\nmodule.exports = ConfirmationDialogController\n")
  const sandbox = { module: { exports: {} } }

  vm.runInNewContext(source, sandbox)
  return sandbox.module.exports
}

test("open shows the confirmation dialog", () => {
  const ConfirmationDialogController = controllerClass()
  let shown = false
  const controller = { dialogTarget: { showModal: () => { shown = true } } }

  ConfirmationDialogController.prototype.open.call(controller)

  assert.equal(shown, true)
})

test("close closes the confirmation dialog", () => {
  const ConfirmationDialogController = controllerClass()
  let closed = false
  const controller = { dialogTarget: { close: () => { closed = true } } }

  ConfirmationDialogController.prototype.close.call(controller)

  assert.equal(closed, true)
})
