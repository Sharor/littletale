# frozen_string_literal: true

require "test_helper"

class GiftMailerTest < ActionMailer::TestCase
  setup do
    @gift = BookGift.create!(
      recipient_name: "Maja",
      recipient_email: "maja@gmail.com",
      sender_callname: "Onkel Alex",
      message: "Denne bog er kun til dig.",
      language: "da",
      title: "Majas eventyr",
      issuance_key: SecureRandom.uuid,
      invitation_token_ciphertext: "placeholder",
      token_digest: Digest::SHA256.hexdigest("invitation-token")
    )
  end

  test "invitation uses the gift language and includes the claim link in both parts" do
    email = GiftMailer.with(gift: @gift, token: "invitation-token", delivery_attempt_id: "attempt-one").invitation

    assert_equal [ "maja@gmail.com" ], email.to
    assert_equal [ "onboarding@resend.dev" ], email.from
    assert_equal "Du har fået en gave fra Onkel Alex!", email.subject
    assert_equal({ idempotency_key: "attempt-one" }, email[:options].unparsed_value)
    assert_match "Hej Maja, du har fået en gave fra LittleTale!", email.html_part.body.to_s
    assert_match "Denne bog er kun til dig.", email.html_part.body.to_s
    assert_no_match %r{<p>\s*<p>}, email.html_part.body.to_s
    invitation_url = Rails.application.routes.url_helpers.gift_invitation_url("invitation-token", host: "example.com")
    assert_match invitation_url, email.html_part.body.to_s
    assert_match "Kærlig hilsen fra dine venner hos LittleTale og Onkel Alex", email.text_part.body.to_s
    assert_match invitation_url, email.text_part.body.to_s
  end

  test "invitation supports Greek" do
    @gift.update!(language: "el", message: "Αυτό το βιβλίο είναι μόνο για σένα.")

    email = GiftMailer.with(gift: @gift, token: "invitation-token",
      delivery_attempt_id: "attempt-two").invitation

    assert_equal "Ένα δώρο από Onkel Alex σε περιμένει!", email.subject
    assert_match "Γεια σου Maja, έχεις ένα δώρο από το LittleTale!", email.html_part.body.to_s
    assert_match "Αυτό το βιβλίο είναι μόνο για σένα.", email.html_part.body.to_s
    assert_match "Με αγάπη από το LittleTale και από Onkel Alex", email.text_part.body.to_s
  end
end
