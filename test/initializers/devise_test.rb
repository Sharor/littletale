# frozen_string_literal: true

require "test_helper"

class DeviseInitializerTest < ActiveSupport::TestCase
  test "Microsoft OAuth uses personal-account endpoints" do
    assert_equal "https://login.microsoftonline.com", MicrosoftOauth::CLIENT_OPTIONS.fetch(:site)
    assert_equal "/consumers/oauth2/v2.0/authorize", MicrosoftOauth::CLIENT_OPTIONS.fetch(:authorize_url)
    assert_equal "/consumers/oauth2/v2.0/token", MicrosoftOauth::CLIENT_OPTIONS.fetch(:token_url)
  end
end
