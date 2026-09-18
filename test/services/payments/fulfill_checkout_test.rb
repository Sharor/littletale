# frozen_string_literal: true

require "test_helper"

class Payments::FulfillCheckoutTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @purchase = BookPurchase.create!(
      user: @user,
      status: "pending",
      product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_book_test",
      stripe_checkout_session_id: "cs_test_paid",
      idempotency_key: SecureRandom.uuid,
      amount_total: 2500,
      currency: "dkk",
      livemode: false
    )
  end

  test "fulfills a verified paid session once" do
    assert_difference -> { BookCredit.count }, 1 do
      assert_difference -> { CharacterCredit.count }, 5 do
        assert Payments::FulfillCheckout.call(session: paid_session)
      end
    end

    assert_no_difference [ -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      assert Payments::FulfillCheckout.call(session: paid_session)
    end
    assert_equal "basic", @user.reload.tier
  end

  test "does not fulfill an unpaid session" do
    session = paid_session.merge("payment_status" => "unpaid")

    assert_raises(Payments::FulfillCheckout::InvalidSession) do
      Payments::FulfillCheckout.call(session: session)
    end

    assert_equal "pending", @purchase.reload.status
    assert_equal 0, @user.book_credits.count
  end

  test "does not fulfill a session with a foreign user or product" do
    session = paid_session
    session["metadata"] = session.fetch("metadata").merge("user_id" => users(:two).id.to_s)

    assert_raises(Payments::FulfillCheckout::InvalidSession) do
      Payments::FulfillCheckout.call(session: session)
    end

    session = paid_session
    session["line_items"]["data"][0]["price"]["product"] = "prod_foreign"
    assert_raises(Payments::FulfillCheckout::InvalidSession) do
      Payments::FulfillCheckout.call(session: session)
    end
  end

  test "does not fulfill a session with the wrong amount currency quantity or environment" do
    [
      paid_session.merge("amount_total" => 1),
      paid_session.merge("currency" => "usd"),
      paid_session.tap { |session| session["line_items"]["data"][0]["quantity"] = 2 },
      paid_session.merge("livemode" => true)
    ].each do |session|
      assert_raises(Payments::FulfillCheckout::InvalidSession) do
        Payments::FulfillCheckout.call(session: session)
      end
    end
    assert_equal 0, @user.book_credits.count
  end

  private

  def paid_session
    {
      "id" => "cs_test_paid",
      "mode" => "payment",
      "payment_status" => "paid",
      "livemode" => false,
      "amount_total" => 2500,
      "currency" => "dkk",
      "customer" => "cus_paid",
      "payment_intent" => "pi_paid",
      "metadata" => {
        "purchase_id" => @purchase.id.to_s,
        "user_id" => @user.id.to_s,
        "product_id" => BookPurchase::PRODUCT_ID
      },
      "line_items" => {
        "data" => [
          {
            "quantity" => 1,
            "price" => {
              "id" => "price_book_test",
              "product" => BookPurchase::PRODUCT_ID,
              "type" => "one_time"
            }
          }
        ]
      }
    }
  end
end
