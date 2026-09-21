# frozen_string_literal: true

require "test_helper"

class Payments::FulfillSubscriptionInvoiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false, stripe_customer_id: "cus_monthly")
    @subscription = @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_subscription_id: "sub_monthly",
      stripe_customer_id: "cus_monthly",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
    @period_start = Time.zone.parse("2026-09-01 00:00:00")
    @period_end = Time.zone.parse("2026-10-01 00:00:00")
  end

  test "a verified paid subscription invoice grants its period exactly once" do
    assert_difference -> { SubscriptionPeriod.count }, 1 do
      2.times { assert Payments::FulfillSubscriptionInvoice.call(invoice: paid_invoice) }
    end

    assert_equal 50, @user.book_credits.monthly_allowance.available.count
    assert_equal 150, @user.character_credits.monthly_allowance.available.count
    assert_equal "sub_monthly", @subscription.reload.stripe_subscription_id
    assert_equal "active", @subscription.status
    assert_equal "basic", @user.reload.tier
  end

  test "accepts the legacy Stripe invoice line and subscription fields" do
    invoice = paid_invoice
    details = invoice.delete("parent").fetch("subscription_details")
    invoice["subscription"] = details.fetch("subscription")
    invoice["subscription_details"] = { "metadata" => details.fetch("metadata") }
    line = invoice.dig("lines", "data", 0)
    line["price"] = {
      "id" => "price_monthly",
      "product" => UserSubscription::PRODUCT_ID,
      "type" => "recurring"
    }
    line.delete("pricing")

    assert Payments::FulfillSubscriptionInvoice.call(invoice: invoice)

    assert_equal 1, @subscription.subscription_periods.count
  end

  test "rejects unpaid foreign or malformed invoices without granting credits" do
    unpaid = paid_invoice.merge("status" => "open")
    foreign_product = paid_invoice.deep_dup
    foreign_product.dig("lines", "data", 0, "pricing", "price_details")["product"] = "prod_foreign"
    foreign_subscription = paid_invoice.deep_dup
    foreign_subscription.dig("parent", "subscription_details")["subscription"] = "sub_foreign"
    foreign_customer = paid_invoice.merge("customer" => "cus_foreign")

    [ unpaid, foreign_product, foreign_subscription, foreign_customer ].each do |invoice|
      assert_raises(Payments::FulfillSubscriptionInvoice::InvalidInvoice) do
        Payments::FulfillSubscriptionInvoice.call(invoice: invoice)
      end
    end
    assert_empty @subscription.subscription_periods
    assert_empty @user.book_credits
  end

  test "ignores an older paid invoice delivered after a newer period" do
    newer = paid_invoice.deep_dup
    newer["id"] = "in_october"
    newer.dig("lines", "data", 0, "period")["start"] = @period_end.to_i
    newer.dig("lines", "data", 0, "period")["end"] = 1.month.from_now(@period_end).to_i
    Payments::FulfillSubscriptionInvoice.call(invoice: newer)

    assert_no_difference [ -> { SubscriptionPeriod.count }, -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      Payments::FulfillSubscriptionInvoice.call(invoice: paid_invoice)
    end

    assert_equal "in_october", @subscription.subscription_periods.sole.stripe_invoice_id
  end

  private

  def paid_invoice
    {
      "id" => "in_september",
      "status" => "paid",
      "livemode" => false,
      "customer" => "cus_monthly",
      "parent" => {
        "type" => "subscription_details",
        "subscription_details" => {
          "subscription" => "sub_monthly",
          "metadata" => {
            "user_subscription_id" => @subscription.id.to_s,
            "user_id" => @user.id.to_s,
            "product_id" => UserSubscription::PRODUCT_ID
          }
        }
      },
      "lines" => {
        "data" => [
          {
            "type" => "subscription",
            "quantity" => 1,
            "period" => { "start" => @period_start.to_i, "end" => @period_end.to_i },
            "pricing" => {
              "type" => "price_details",
              "price_details" => {
                "price" => "price_monthly",
                "product" => UserSubscription::PRODUCT_ID
              }
            }
          }
        ]
      }
    }
  end
end
