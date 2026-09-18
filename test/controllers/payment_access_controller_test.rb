# frozen_string_literal: true

require "test_helper"

class PaymentAccessControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @user.tutorial.update!(terms: true)
    grant_paid_bundle
    sign_in @user.reload
  end

  test "zero book credits prompts on character entry but Continue works while character credits remain" do
    consume_book_credit

    get characters_url

    assert_response :success
    assert_select "[role='dialog'][aria-modal='true']" do
      assert_select "h2", text: /out of book credits/i
      assert_select "a[href='#{characters_path(continue: 1)}']", text: /Continue to characters/
    end

    get characters_url(continue: 1)
    assert_response :success
    assert_select "[role='dialog'][aria-modal='true']", count: 0
  end

  test "zero book and character credits block direct character entry" do
    exhaust_both_balances

    get characters_url

    assert_redirected_to settings_url(payment_required: "both")
  end

  test "zero book and character credits disable links into the character library" do
    book = @user.books.create!(name: "Blocked character review", total_pages: 1,
      generation_status: :failed, generation_failure: {
      "type" => "character_image_not_ready",
      "message" => "A character image needs attention."
    })
    exhaust_both_balances

    get book_url(book)

    assert_response :success
    assert_select "a[href='#{characters_path}']", count: 0
    assert_select "[data-character-route-disabled][aria-disabled='true']", text: /Review character images/
  end

  test "zero character credits disable new character creation but preserve existing character selection" do
    @user.character_credits.update_all(status: "consumed")

    get characters_url
    assert_response :success
    assert_select "[data-new-character-disabled][aria-disabled='true']"
    assert_select "a[aria-label^='Edit ']"

    get new_character_url
    assert_redirected_to settings_url(payment_required: "character")
  end

  test "zero character credits reject direct character generation submissions without persisting changes" do
    @user.character_credits.update_all(status: "consumed")
    character = @user.characters.first!
    original_hair_color = character.hair_color

    assert_no_difference("Character.count") do
      post characters_url, params: { character: valid_character_params.merge("draft-1" => "") }
    end
    assert_redirected_to settings_url(payment_required: "character")

    patch character_url(character), params: {
      character: valid_character_params.merge(hair_color: "Purple")
    }
    assert_redirected_to settings_url(payment_required: "character")
    assert_equal original_hair_color, character.reload.hair_color
  end

  test "zero character credits still allow metadata-only edits that reuse an existing request" do
    character = @user.characters.first!
    request = CharacterImageRequest.submit!(character)
    request.character_credit_reservations.held.first.consume!
    @user.character_credits.update_all(status: "consumed")

    assert_no_difference("CharacterImageRequest.count") do
      patch character_url(character), params: {
        character: character_params_for(character).merge(name: "Renamed character")
      }
    end

    assert_redirected_to characters_url
    assert_equal "Renamed character", character.reload.name
    assert_equal request, character.current_image_request
  end

  test "zero book credits disable book generation routes and controls" do
    consume_book_credit

    get books_url
    assert_response :success
    assert_select "[data-new-book-disabled][aria-disabled='true']"

    get new_book_url
    assert_redirected_to settings_url(payment_required: "book")
  end

  test "administrators bypass empty credit gates" do
    @user.update!(admin: true)
    exhaust_both_balances

    get characters_url
    assert_response :success
    get new_book_url
    assert_response :success
  end

  test "direct JSON generation gates return payment-required details" do
    exhaust_both_balances

    get characters_url(format: :json)
    assert_response :payment_required
    assert_equal settings_url, response.parsed_body.fetch("settings_url")

    get new_character_url(format: :json)
    assert_response :payment_required
    assert_equal "character_credit_required", response.parsed_body.fetch("error")

    get new_book_url(format: :json)
    assert_response :payment_required
    assert_equal "book_credit_required", response.parsed_body.fetch("error")

    post books_url(format: :json), params: {
      book: { name: "Blocked JSON book", plot: "Adventure", total_pages: 1 }
    }
    assert_response :payment_required
    assert_equal settings_url, response.parsed_body.fetch("settings_url")
  end

  private

  def grant_paid_bundle
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_access", payment_intent_id: "pi_access",
      stripe_customer_id: "cus_access", price_id: "price_access", amount_total: 2500, currency: "dkk")
  end

  def consume_book_credit
    @user.book_credits.update_all(status: "consumed")
  end

  def exhaust_both_balances
    consume_book_credit
    @user.character_credits.update_all(status: "consumed")
  end

  def valid_character_params
    {
      name: "Blocked character",
      age: 8,
      gender: "Girl",
      ethnicity: "Danish",
      hair_color: "Brown",
      hair_style: "Long",
      eye_color: "Blue",
      roles: [ "Hero" ],
      creation_mode: "form"
    }
  end

  def character_params_for(character)
    {
      name: character.name,
      age: character.age,
      gender: character.gender,
      ethnicity: character.ethnicity,
      hair_color: character.hair_color,
      hair_style: character.hair_style,
      eye_color: character.eye_color,
      roles: character.roles,
      creation_mode: character.creation_mode
    }
  end
end
