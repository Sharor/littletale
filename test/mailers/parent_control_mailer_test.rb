# frozen_string_literal: true

require "test_helper"

class ParentControlMailerTest < ActionMailer::TestCase
  test "pin reset goes to the registered email with a time-limited link" do
    user = users(:one)
    control = user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    email = ParentControlMailer.with(control: control).pin_reset

    assert_equal [ user.email ], email.to
    assert_equal [ "hello@minortale.com" ], email.from
    assert_equal [ "MinorTale" ], email[:from].display_names
    assert_equal "Reset your MinorTale parent PIN", email.subject
    assert_match "MinorTale account", email.html_part.body.to_s
    assert_match "/parent/pin_reset/edit?token=", email.html_part.body.to_s
    assert_match "This link expires in 30 minutes", email.text_part.body.to_s
  end
end
