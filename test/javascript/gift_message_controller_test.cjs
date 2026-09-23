const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function controllerInstance(message = "English default") {
  const source = fs.readFileSync("app/javascript/controllers/gift_message_controller.js", "utf8")
    .replace(/import .*\n/, "class Controller {}\n")
    .replace("export default class", "globalThis.GiftMessageController = class")
  const context = {}
  vm.runInNewContext(source, context)
  const controller = new context.GiftMessageController()
  controller.enValue = "English default"
  controller.daValue = "Dansk standard"
  controller.languageTarget = { value: "en" }
  controller.messageTarget = { value: message }
  controller.previewTarget = { textContent: message }
  controller.connect()
  return controller
}

test("changing language replaces an untouched default message", () => {
  const controller = controllerInstance()
  controller.languageTarget.value = "da"

  controller.changeLanguage()

  assert.equal(controller.messageTarget.value, "Dansk standard")
  assert.equal(controller.previewTarget.textContent, "Dansk standard")
})

test("changing language preserves a customized message", () => {
  const controller = controllerInstance()
  controller.messageTarget.value = "My own message"
  controller.markCustomized()
  controller.languageTarget.value = "da"

  controller.changeLanguage()

  assert.equal(controller.messageTarget.value, "My own message")
  assert.equal(controller.previewTarget.textContent, "My own message")
})


test("reconnecting after validation preserves a customized message", () => {
  const controller = controllerInstance("My submitted message")
  controller.languageTarget.value = "da"

  controller.changeLanguage()

  assert.equal(controller.messageTarget.value, "My submitted message")
})
