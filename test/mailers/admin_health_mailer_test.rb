require "test_helper"

class AdminHealthMailerTest < ActionMailer::TestCase
  test "addresses the production check to the requesting administrator" do
    admin = users(:three)
    admin.update!(admin: true)

    email = AdminHealthMailer.with(
      admin: admin,
      locale: :en,
      idempotency_key: "health-email-123"
    ).test_email

    assert_equal [ admin.email ], email.to
    assert_equal [ "hello@minortale.com" ], email.from
    assert_equal [ "MinorTale" ], email[:from].display_names
    assert_equal "MinorTale production email check", email.subject
    assert_equal({ idempotency_key: "health-email-123" }, email[:options].unparsed_value)
    assert_match "This email confirms that MinorTale can submit mail", email.text_part.body.to_s
    assert_match admin.email, email.html_part.body.to_s
  end
end
