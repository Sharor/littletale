# frozen_string_literal: true

require "test_helper"

class UserSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false, stripe_customer_id: nil)
    @subscription = @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  test "a paid initial period grants a hidden monthly allowance exactly once" do
    period_start = Time.zone.parse("2026-09-01 00:00:00")
    period_end = Time.zone.parse("2026-10-01 00:00:00")

    assert_difference -> { BookCredit.count }, 50 do
      assert_difference -> { CharacterCredit.count }, 150 do
        2.times do
          @subscription.activate_period!(
            stripe_subscription_id: "sub_monthly",
            stripe_invoice_id: "in_september",
            stripe_customer_id: "cus_monthly",
            price_id: "price_monthly",
            period_start: period_start,
            period_end: period_end
          )
        end
      end
    end

    assert_equal 50, @user.book_credits.monthly_allowance.available.count
    assert_equal 150, @user.character_credits.monthly_allowance.available.count
    assert_equal 0, @user.available_book_credits
    assert_equal 0, @user.available_character_credits
    assert_equal "basic", @user.reload.tier
    assert_equal "active", @subscription.reload.status
    assert_equal "sub_monthly", @subscription.stripe_subscription_id
    assert_equal period_end, @subscription.current_period_end
  end

  test "renewal tops up the shared visible pool to its caps and resets the hidden allowance" do
    september_start = Time.zone.parse("2026-09-01 00:00:00")
    october_start = Time.zone.parse("2026-10-01 00:00:00")
    november_start = Time.zone.parse("2026-11-01 00:00:00")
    activate_period("in_september", september_start, october_start)

    @user.book_credits.monthly_allowance.available.limit(7).update_all(status: "consumed")
    @user.character_credits.monthly_allowance.available.limit(145).update_all(status: "consumed")

    activate_period("in_october", october_start, november_start)

    assert_equal 10, @user.reload.available_book_credits
    assert_equal 5, @user.available_character_credits
    assert_equal 50, @user.book_credits.monthly_allowance.available.count
    assert_equal 150, @user.character_credits.monthly_allowance.available.count
    assert_equal 0, @user.book_credits.monthly_allowance.where(expires_at: october_start).available.count
    assert_equal 0, @user.character_credits.monthly_allowance.where(expires_at: october_start).available.count
  end

  test "renewal never reduces or tops up a visible balance already above the saved caps" do
    september_start = Time.zone.parse("2026-09-01 00:00:00")
    october_start = Time.zone.parse("2026-10-01 00:00:00")
    november_start = Time.zone.parse("2026-11-01 00:00:00")
    activate_period("in_september", september_start, october_start)
    @user.book_credits.monthly_allowance.available.limit(12).update_all(visible: true, expires_at: nil)
    @user.character_credits.monthly_allowance.available.limit(25).update_all(visible: true, expires_at: nil)

    activate_period("in_october", october_start, november_start)

    assert_equal 12, @user.reload.available_book_credits
    assert_equal 25, @user.available_character_credits
  end

  test "a lifecycle sync for the next period cannot suppress its later paid invoice" do
    september_start = Time.zone.parse("2026-09-01 00:00:00")
    october_start = Time.zone.parse("2026-10-01 00:00:00")
    november_start = Time.zone.parse("2026-11-01 00:00:00")
    activate_period("in_september", september_start, october_start)
    @subscription.update!(current_period_start: october_start, current_period_end: november_start)

    activate_period("in_october", october_start, november_start)

    assert_equal 2, @subscription.subscription_periods.count
    assert_equal 50, @user.book_credits.monthly_allowance.available.count
    assert_equal 150, @user.character_credits.monthly_allowance.available.count
  end

  test "ending a subscription saves from the final allowance without granting a new period" do
    period_start = Time.zone.parse("2026-09-01 00:00:00")
    period_end = Time.zone.parse("2026-10-01 00:00:00")
    activate_period("in_september", period_start, period_end)
    @user.book_credits.monthly_allowance.available.limit(42).update_all(status: "consumed")
    @user.character_credits.monthly_allowance.available.limit(132).update_all(status: "consumed")

    @subscription.end!(ended_at: period_end)
    @subscription.end!(ended_at: period_end)

    assert_equal 8, @user.reload.available_book_credits
    assert_equal 18, @user.available_character_credits
    assert_equal 0, @user.book_credits.monthly_allowance.available.count
    assert_equal 0, @user.character_credits.monthly_allowance.available.count
    assert_equal "canceled", @subscription.reload.status
    assert_equal period_end, @subscription.ended_at
  end

  test "ending early prevents held allowance from returning when reservations release" do
    period_end = 1.month.from_now
    activate_period("in_september", Time.current, period_end)
    book = @user.books.create!(name: "Canceled reservation", total_pages: 1)
    book_reservation = BookCredit.reserve_for!(book)
    character_reservation = CharacterCredit.reserve_for!(character_request("Cancellation character"))
    ended_at = Time.current

    travel_to(ended_at) { @subscription.end!(ended_at: ended_at) }
    travel_to(ended_at + 1.second) do
      book_reservation.release!(reason: "generation_failed")
      character_reservation.release!(reason: "generation_failed")
    end

    assert_equal "expired", book_reservation.book_credit.reload.status
    assert_equal "expired", character_reservation.character_credit.reload.status
    assert_equal 10, @user.reload.available_book_credits
    assert_equal 20, @user.available_character_credits
  end

  test "a delayed paid period cannot reactivate a canceled Stripe subscription" do
    september_start = Time.zone.parse("2026-09-01 00:00:00")
    october_start = Time.zone.parse("2026-10-01 00:00:00")
    november_start = Time.zone.parse("2026-11-01 00:00:00")
    activate_period("in_september", september_start, october_start)
    @subscription.end!(ended_at: october_start)

    assert_no_difference [ -> { SubscriptionPeriod.count }, -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      activate_period("in_october", october_start, november_start)
    end

    assert_equal "canceled", @subscription.reload.status
    assert_equal october_start, @subscription.ended_at
  end

  test "funding spends hidden monthly books before visible purchased credits" do
    purchase = fulfill_purchase
    activate_period("in_september", Time.current, 1.month.from_now)
    book = @user.books.create!(name: "Subscription funded", total_pages: 1)

    reservation = BookCredit.reserve_for!(book)

    assert_not reservation.book_credit.visible?
    assert_nil reservation.book_credit.book_purchase_id
    assert_equal purchase.book_credit, @user.book_credits.visible.available.first
    assert_equal 1, @user.available_book_credits
  end

  test "funding uses the shared visible pool after the monthly allowance is exhausted" do
    purchase = fulfill_purchase
    activate_period("in_september", Time.current, 1.month.from_now)
    @user.book_credits.monthly_allowance.update_all(status: "consumed")
    book = @user.books.create!(name: "Visible funded", total_pages: 1)

    reservation = BookCredit.reserve_for!(book)

    assert_equal purchase.book_credit, reservation.book_credit
    assert_equal 0, @user.available_book_credits
  end

  test "generation remains available while only hidden allowance remains" do
    activate_period("in_september", Time.current, 1.month.from_now)

    assert @user.reload.book_generation_available?
    assert @user.character_generation_available?
    assert_equal 0, @user.available_book_credits
    assert_equal 0, @user.available_character_credits
  end

  test "an expired hidden reservation cannot return to the next monthly allowance" do
    period_end = 1.month.from_now
    activate_period("in_september", Time.current, period_end)
    book = @user.books.create!(name: "Expired reservation", total_pages: 1)
    reservation = BookCredit.reserve_for!(book)

    travel_to(period_end + 1.second) do
      assert reservation.release!(reason: "generation_failed")
    end

    assert_equal "expired", reservation.book_credit.reload.status
  end

  test "character funding spends hidden allowance before visible purchased credits" do
    purchase = fulfill_purchase
    activate_period("in_september", Time.current, 1.month.from_now)
    character = @user.characters.create!(
      name: "Subscription character",
      age: 8,
      gender: "Girl",
      ethnicity: "White",
      hair_color: "Brown",
      hair_style: "Long",
      eye_color: "Blue",
      roles: [ "Hero" ],
      creation_mode: "form"
    )
    assessment = @user.character_image_assessments.create!(
      fingerprint: SecureRandom.hex,
      prompt: "storybook character",
      generation_model: "gpt-image-1",
      policy_version: CharacterImageAssessment::POLICY_VERSION,
      status: "approved"
    )
    request = @user.character_image_requests.create!(
      character: character,
      original_character_id: character.id,
      assessment: assessment
    )

    reservation = CharacterCredit.reserve_for!(request)

    assert_not reservation.character_credit.visible?
    assert_equal 5, purchase.character_credits.available.count
    assert_equal 5, @user.available_character_credits
  end

  private

  def activate_period(invoice_id, period_start, period_end)
    @subscription.activate_period!(
      stripe_subscription_id: "sub_monthly",
      stripe_invoice_id: invoice_id,
      stripe_customer_id: "cus_monthly",
      price_id: "price_monthly",
      period_start: period_start,
      period_end: period_end
    )
  end

  def fulfill_purchase
    purchase = @user.book_purchases.create!(
      status: "pending",
      product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
    purchase.fulfill!(
      checkout_session_id: "cs_#{SecureRandom.hex}",
      payment_intent_id: "pi_#{SecureRandom.hex}",
      stripe_customer_id: "cus_monthly",
      price_id: "price_book",
      amount_total: 2500,
      currency: "dkk"
    )
    purchase
  end

  def character_request(name)
    character = @user.characters.create!(
      name: name,
      age: 8,
      gender: "Girl",
      ethnicity: "White",
      hair_color: "Brown",
      hair_style: "Long",
      eye_color: "Blue",
      roles: [ "Hero" ],
      creation_mode: "form"
    )
    assessment = @user.character_image_assessments.create!(
      fingerprint: SecureRandom.hex,
      prompt: "storybook character",
      generation_model: "gpt-image-1",
      policy_version: CharacterImageAssessment::POLICY_VERSION,
      status: "approved"
    )
    @user.character_image_requests.create!(
      character: character,
      original_character_id: character.id,
      assessment: assessment
    )
  end
end
