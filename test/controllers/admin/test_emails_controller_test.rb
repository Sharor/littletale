require "test_helper"
require "minitest/mock"

class Admin::TestEmailsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "an administrator sends directly to their own account" do
    administrator = admin
    sign_in administrator

    assert_no_enqueued_jobs do
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        post admin_test_email_path, params: { recipient: "someone-else@example.com" }
      end
    end

    assert_redirected_to admin_root_path
    assert_equal [ administrator.email ], ActionMailer::Base.deliveries.last.to
  end

  test "a non-admin cannot send a test email" do
    sign_in users(:one)

    assert_no_difference("ActionMailer::Base.deliveries.size") do
      post admin_test_email_path
    end

    assert_response :forbidden
  end

  test "a delivery error is reported without exposing provider details" do
    sign_in admin
    delivery = Object.new
    delivery.define_singleton_method(:deliver_now) { raise "secret provider response" }
    mailer = Object.new
    mailer.define_singleton_method(:test_email) { delivery }

    AdminHealthMailer.stub(:with, mailer) do
      post admin_test_email_path
    end

    assert_redirected_to admin_root_path
    assert_equal "The test email could not be submitted.", flash[:alert]
    assert_no_match "secret", flash[:alert]
  end

  private
    def admin
      users(:three).tap { |user| user.update!(admin: true) }
    end
end
