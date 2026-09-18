# frozen_string_literal: true

require "test_helper"

class PaymentCreditTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @purchase = BookPurchase.create!(
      user: @user,
      status: "pending",
      product_id: "prod_VHc1FYY2QqVlJ0",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  test "fulfilling one purchase upgrades the user and grants the bundle exactly once" do
    assert_difference -> { BookCredit.count }, 1 do
      assert_difference -> { CharacterCredit.count }, 5 do
        @purchase.fulfill!(
          checkout_session_id: "cs_test_bundle",
          payment_intent_id: "pi_test_bundle",
          stripe_customer_id: "cus_test_bundle",
          price_id: "price_test_bundle",
          amount_total: 2500,
          currency: "dkk"
        )
      end
    end

    assert_no_difference [ -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      @purchase.fulfill!(
        checkout_session_id: "cs_test_bundle",
        payment_intent_id: "pi_test_bundle",
        stripe_customer_id: "cus_test_bundle",
        price_id: "price_test_bundle",
        amount_total: 2500,
        currency: "dkk"
      )
    end

    assert_equal "basic", @user.reload.tier
    assert_equal "paid", @purchase.reload.status
    assert_equal 1, @user.available_book_credits
    assert_equal 5, @user.available_character_credits
  end

  test "a book purchase does not downgrade an existing higher tier" do
    @user.update!(tier: "premium")

    fulfill_purchase

    assert_equal "premium", @user.reload.tier
    assert_equal 1, @user.available_book_credits
  end

  test "a book credit is reserved once and can be released for reuse" do
    fulfill_purchase
    first_book = @user.books.create!(name: "First paid book", total_pages: 1)
    second_book = @user.books.create!(name: "Second paid book", total_pages: 1)

    reservation = BookCredit.reserve_for!(first_book)

    assert_equal reservation, BookCredit.reserve_for!(first_book)
    assert_equal 0, @user.available_book_credits
    assert_raises(BookCredit::LimitReached) { BookCredit.reserve_for!(second_book) }

    assert reservation.release!(reason: "queue_enqueue_failed")
    assert_not reservation.release!(reason: "queue_enqueue_failed")
    assert_equal 1, @user.available_book_credits
    assert BookCredit.reserve_for!(second_book)
  end

  test "a consumed book credit cannot be reused" do
    fulfill_purchase
    book = @user.books.create!(name: "Completed paid book", total_pages: 1)
    reservation = BookCredit.reserve_for!(book)

    assert reservation.consume!
    assert_not reservation.release!(reason: "admin_released_failed_book")
    assert_equal "consumed", reservation.reload.status
    assert_equal "consumed", reservation.book_credit.reload.status
    assert_equal 0, @user.available_book_credits
  end

  test "character credits reserve independently from book credits" do
    fulfill_purchase
    character = @user.characters.create!(valid_character_attributes)
    assessment = CharacterImageAssessment.create!(
      user: @user,
      fingerprint: SecureRandom.hex,
      prompt: "A friendly storybook character",
      generation_model: "gpt-image-1",
      policy_version: CharacterImageAssessment::POLICY_VERSION,
      status: "approved"
    )
    request = CharacterImageRequest.create!(user: @user, character: character, assessment: assessment,
      original_character_id: character.id)

    reservation = CharacterCredit.reserve_for!(request)

    assert_equal reservation, CharacterCredit.reserve_for!(request)
    assert_equal 4, @user.available_character_credits
    assert_equal 1, @user.available_book_credits
  end

  test "different Stripe events cannot grant a second bundle for one Checkout session" do
    fulfill_purchase
    duplicate = BookPurchase.create!(
      user: @user,
      status: "pending",
      product_id: "prod_VHc1FYY2QqVlJ0",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      duplicate.fulfill!(
        checkout_session_id: "cs_test_bundle",
        payment_intent_id: "pi_other",
        stripe_customer_id: "cus_test_bundle",
        price_id: "price_test_bundle",
        amount_total: 2500,
        currency: "dkk"
      )
    end

    assert_equal 1, @user.available_book_credits
    assert_equal 5, @user.available_character_credits
  end

  private

  def fulfill_purchase
    @purchase.fulfill!(
      checkout_session_id: "cs_test_bundle",
      payment_intent_id: "pi_test_bundle",
      stripe_customer_id: "cus_test_bundle",
      price_id: "price_test_bundle",
      amount_total: 2500,
      currency: "dkk"
    )
  end

  def valid_character_attributes
    {
      name: "Credit hero",
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
end
