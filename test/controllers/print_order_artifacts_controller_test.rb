# frozen_string_literal: true

require "test_helper"

class PrintOrderArtifactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    @previous_host = ENV["LULU_ASSET_HOST"]
    ENV["LULU_ASSET_HOST"] = "https://assets.example.test"
    ENV["LULU_ORDERS_ENABLED"] = "true"
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Signed files", total_pages: 1, language: "en", generation_status: :completed)
    page = book.pages.create!(text: "A retained page.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A printed forest")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
    @order.reload
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
    ENV["LULU_ASSET_HOST"] = @previous_host
  end

  test "serves a current PDF through an expiring signed URL without a user session" do
    url = Lulu::ArtifactUrl.for(order: @order, kind: :interior)

    assert_equal "assets.example.test", URI(url).host
    get URI(url).request_uri

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF-")
  end

  test "rejects a tampered artifact token" do
    url = Lulu::ArtifactUrl.for(order: @order, kind: :cover)
    uri = URI(url)
    uri.path = uri.path.sub(/.(?=\/cover\.pdf\z)/, "x")

    get uri.request_uri

    assert_response :not_found
  end
end
