# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class DeliverGiftEmailJobTest < ActiveJob::TestCase
  setup do
    @gift = BookGift.create!(
      recipient_name: "Reader",
      recipient_email: "reader@gmail.com",
      sender_callname: "Alex",
      message: "A story for you.",
      language: "en",
      title: "The Gift",
      issuance_key: SecureRandom.uuid,
      invitation_token_ciphertext: BookGift.send(:encrypt_token, "gift-token"),
      token_digest: Digest::SHA256.hexdigest("gift-token"),
      delivery_status: "queued",
      delivery_attempt_id: "attempt-one",
      email_queued_at: Time.current
    )
  end

  test "invitation tokens are excluded from job logs" do
    assert_not DeliverGiftEmailJob.log_arguments
  end

  test "provider acceptance marks the gift sent" do
    assert_difference("ActionMailer::Base.deliveries.size", 1) do
      DeliverGiftEmailJob.perform_now(@gift.id, "attempt-one")
    end

    assert_equal "sent", @gift.reload.delivery_status
    assert_not_nil @gift.delivered_at
    assert_nil @gift.delivery_error
  end

  test "a stale delivery attempt cannot send or overwrite the current attempt" do
    @gift.update!(delivery_attempt_id: "attempt-two")

    assert_no_difference("ActionMailer::Base.deliveries.size") do
      DeliverGiftEmailJob.perform_now(@gift.id, "attempt-one")
    end

    assert_equal "queued", @gift.reload.delivery_status
    assert_equal "attempt-two", @gift.delivery_attempt_id
  end

  test "transport error marks the gift failed and reraises for job infrastructure" do
    delivery = Object.new
    delivery.define_singleton_method(:invitation) { self }
    delivery.define_singleton_method(:deliver_now!) { raise Resend::Error, "provider unavailable" }

    GiftMailer.stub(:with, delivery) do
      assert_raises(Resend::Error) { DeliverGiftEmailJob.perform_now(@gift.id, "attempt-one") }
    end

    assert_equal "failed", @gift.reload.delivery_status
    assert_match "provider unavailable", @gift.delivery_error
    assert_nil @gift.delivered_at
  end
end
