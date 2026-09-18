# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CharacterFundingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @character = @user.characters.create!(valid_character_attributes)
  end

  test "a new Basic character request reserves one character credit" do
    fulfill_purchase

    request = CharacterImageRequest.submit!(@character)

    assert_equal "credit", request.funding_source
    assert_predicate request.character_credit_reservations.held, :exists?
    assert_equal 4, @user.reload.available_character_credits
    assert_equal 1, @user.available_book_credits
  end

  test "submitting the same request twice does not reserve another credit" do
    fulfill_purchase

    first = CharacterImageRequest.submit!(@character)
    second = CharacterImageRequest.submit!(@character)

    assert_equal first, second
    assert_equal 1, @user.character_credit_reservations.count
    assert_equal 4, @user.available_character_credits
  end

  test "a trial request keeps trial funding after the account upgrades" do
    request = CharacterImageRequest.submit!(@character)
    fulfill_purchase

    assert_equal "trial", request.reload.funding_source
    assert_nil CharacterFunding.reserve_for!(request)
    assert_equal 5, @user.reload.available_character_credits
  end

  test "screening rejection releases a paid character credit before generation" do
    fulfill_purchase
    @character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png",
      content_type: "image/png")
    request = CharacterImageRequest.submit!(@character)

    request.assessment.resolve!(outcome: "rejected", source: "automatic",
      internal_reason: "not suitable", public_reason: "Choose another photo")

    assert_equal "released", request.character_credit_reservations.last.reload.status
    assert_equal 5, @user.reload.available_character_credits
  end

  test "an initial generation queue failure releases its character credit" do
    fulfill_purchase
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    request = GenerateCharacterImageJob.stub(:perform_later, failed_job) do
      CharacterImageRequest.submit!(@character)
    end

    assert_equal "released", request.character_credit_reservations.last.reload.status
    assert_equal 5, @user.reload.available_character_credits
  end

  test "an initial screening queue failure releases its character credit" do
    fulfill_purchase
    @character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png",
      content_type: "image/png")
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    request = ScreenCharacterImageJob.stub(:perform_later, failed_job) do
      CharacterImageRequest.submit!(@character)
    end

    assert_equal "released", request.character_credit_reservations.last.reload.status
    assert_equal 5, @user.reload.available_character_credits
  end

  test "a Basic request requires an available character credit" do
    @user.update!(tier: "basic")

    assert_no_difference("CharacterImageRequest.count") do
      assert_raises(CharacterCredit::LimitReached) do
        CharacterImageRequest.submit!(@character)
      end
    end
    assert_nil @character.reload.current_image_request_id
  end

  test "Basic users retain the per-character retry limit without the old account-wide ceiling" do
    fulfill_purchase
    filler = @user.characters.create!(valid_character_attributes.merge(name: "Filler"))
    Character::TRIAL_USER_LIMIT.times do
      @user.action_logs.create!(action: "setup_illustration", trackable: filler)
    end

    assert @character.can_perform_action?("setup_illustration")
    assert CharacterImageRequest.submit!(@character).generation_attempt
  end

  test "a stale admin retry does not reacquire a released character credit" do
    fulfill_purchase
    request = CharacterImageRequest.submit!(@character)
    request.generation_attempt.update!(status: "failed")
    request.character_credit_reservations.held.first.release!(reason: "admin_released_failed_character")
    admin = users(:three)
    admin.update!(admin: true)

    assert_not request.admin_retry_generation!(admin: admin, expected_version: "stale")
    assert_not_predicate request.character_credit_reservations.held, :exists?
    assert_equal 5, @user.reload.available_character_credits
  end

  test "reaching the per-character limit does not reserve an unusable credit" do
    fulfill_purchase
    Character::TRIAL_CHARACTER_LIMIT.times do
      @character.action_logs.create!(action: "setup_illustration", user: @user)
    end

    request = nil
    assert_no_difference("@user.character_credit_reservations.count") do
      request = CharacterImageRequest.submit!(@character)
    end

    assert_nil request.generation_attempt
    assert_equal 5, @user.reload.available_character_credits
  end

  test "resubmitting a screening-rejected request does not reacquire a credit" do
    fulfill_purchase
    @character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png",
      content_type: "image/png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "rejected", source: "automatic",
      internal_reason: "not suitable", public_reason: "Choose another photo")

    assert_no_difference("@user.character_credit_reservations.count") do
      assert_equal request, CharacterImageRequest.submit!(@character)
    end

    assert_not_predicate request.character_credit_reservations.held, :exists?
    assert_equal 5, @user.reload.available_character_credits
  end

  test "a stale generation job cannot run after its character credit was released" do
    fulfill_purchase
    request = CharacterImageRequest.submit!(@character)
    attempt = request.generation_attempt
    request.character_credit_reservations.held.first.release!(reason: "admin_released_failed_character")

    CharacterImageGeneration.stub(:call, ->(*) { flunk "released work must not reach the provider" }) do
      GenerateCharacterImageJob.perform_now(attempt.id)
    end

    assert_equal "reserved", attempt.reload.status
    assert_equal 5, @user.reload.available_character_credits
  end

  private

  def fulfill_purchase
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_#{SecureRandom.hex}", payment_intent_id: "pi_#{SecureRandom.hex}",
      stripe_customer_id: "cus_character_funding_#{@user.id}", price_id: "price_test",
      amount_total: 2500, currency: "dkk")
  end

  def valid_character_attributes
    {
      name: "Credit character",
      age: 8,
      gender: "Girl",
      ethnicity: "White",
      hair_color: "Brown",
      hair_style: "Long",
      eye_color: "Blue",
      roles: [ "Hero" ],
      creation_mode: "form"
    }
  end
end
