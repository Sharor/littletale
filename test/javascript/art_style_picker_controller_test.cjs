const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function controllerInstance(selectedOption = null) {
  const source = fs.readFileSync("app/javascript/controllers/art_style_picker_controller.js", "utf8")
    .replace(/import .*\n/, "class Controller {}\n")
    .replace("export default class", "globalThis.ArtStylePickerController = class")
  const context = {}
  vm.runInNewContext(source, context)
  const controller = new context.ArtStylePickerController()
  controller.previewTarget = { src: "/old.webp", alt: "Old preview" }
  controller.nameTarget = { textContent: "Old style" }
  controller.element = { querySelector: () => selectedOption }
  return controller
}

test("selecting a style updates the featured image, description, and name", () => {
  const controller = controllerInstance()

  controller.select({ currentTarget: { dataset: {
    preview: "/assets/art_styles/claymation_plasticine.webp",
    alt: "Claymation / Plasticine art style preview",
    name: "Claymation / Plasticine"
  } } })

  assert.equal(controller.previewTarget.src, "/assets/art_styles/claymation_plasticine.webp")
  assert.equal(controller.previewTarget.alt, "Claymation / Plasticine art style preview")
  assert.equal(controller.nameTarget.textContent, "Claymation / Plasticine")
})

test("connecting synchronizes the featured preview with a restored selection", () => {
  const selectedOption = { dataset: {
    preview: "/assets/art_styles/paper_cutout.webp",
    alt: "Paper Cutout art style preview",
    name: "Paper Cutout"
  } }
  const controller = controllerInstance(selectedOption)

  controller.connect()

  assert.equal(controller.previewTarget.src, "/assets/art_styles/paper_cutout.webp")
  assert.equal(controller.previewTarget.alt, "Paper Cutout art style preview")
  assert.equal(controller.nameTarget.textContent, "Paper Cutout")
})
