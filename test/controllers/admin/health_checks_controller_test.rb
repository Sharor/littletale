require "test_helper"
require "minitest/mock"

class Admin::HealthChecksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  test "an administrator can run all checks without enqueueing work or recording generation history" do
    sign_in admin
    storage_check = Struct.new(:call).new(
      HealthChecks::Result.new(
        name: "object_storage", status: "connected", message: "Storage connected.",
        checked_at: "2026-10-03T10:00:00Z", duration_ms: 12
      )
    )
    openai_check = Struct.new(:call).new(
      HealthChecks::Result.new(
        name: "openai", status: "failed", message: "OpenAI unavailable.",
        checked_at: "2026-10-03T10:00:01Z", duration_ms: 31
      )
    )
    gemini_check = Struct.new(:call).new(
      HealthChecks::Result.new(
        name: "gemini", status: "connected", message: "Gemini connected.",
        checked_at: "2026-10-03T10:00:02Z", duration_ms: 22
      )
    )

    HealthChecks::ObjectStorage.stub(:new, -> { storage_check }) do
      HealthChecks::Openai.stub(:new, -> { openai_check }) do
        HealthChecks::Gemini.stub(:new, -> { gemini_check }) do
          assert_no_difference("GenerationProviderRequest.count") do
            assert_no_enqueued_jobs { post admin_health_check_path }
          end
        end
      end
    end

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_select "[data-health-check='object_storage'][data-health-status='connected']", text: /Storage connected/
    assert_select "[data-health-check='openai'][data-health-status='failed']", text: /OpenAI unavailable/
    assert_select "[data-health-check='gemini'][data-health-status='connected']", text: /Gemini connected/
    assert_select "time[datetime='2026-10-03T10:00:00Z']", text: /12 ms/
  end

  test "a non-admin cannot trigger external checks" do
    sign_in users(:one)
    forbidden_check = -> { flunk "health check must not be constructed" }

    HealthChecks::ObjectStorage.stub(:new, forbidden_check) do
      HealthChecks::Openai.stub(:new, forbidden_check) do
        HealthChecks::Gemini.stub(:new, forbidden_check) do
          post admin_health_check_path
        end
      end
    end

    assert_response :forbidden
  end

  private
    def admin
      users(:three).tap { |user| user.update!(admin: true) }
    end
end
