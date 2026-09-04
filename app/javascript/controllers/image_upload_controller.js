import { Controller } from "@hotwired/stimulus"

// Helper to get CSRF token from meta tag
function getCsrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta && meta.getAttribute("content")
}

export default class extends Controller {
  preview(event) {
    const file = event.target.files[0]
    if (!file) return

    const formData = new FormData()
    formData.append("photo", file)

    fetch("/characters/photo_preview", {
      method: "POST",
      headers: {
        "Accept": "text/html",
        "X-CSRF-Token": getCsrfToken()
      },
      body: formData
    })
    .then(response => response.text())
    .then(html => {
      document.getElementById("image_preview").innerHTML = html
    })
  }
}