# frozen_string_literal: true

require "test_helper"

class Lulu::ArtifactRequestLoggerTest < ActiveSupport::TestCase
  test "redacts signed artifact capabilities from Rails request-start logs" do
    token = "signed-private-capability"
    request = ActionDispatch::Request.new(
      Rack::MockRequest.env_for("/lulu-files/#{token}/interior.pdf")
    )
    logger = Lulu::ArtifactRequestLogger.new(->(_env) { [ 200, {}, [] ] })

    message = logger.send(:started_request_message, request)

    assert_includes message, "/lulu-files/[FILTERED]/interior.pdf"
    assert_not_includes message, token
  end

  test "leaves ordinary request paths unchanged" do
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/orders"))
    logger = Lulu::ArtifactRequestLogger.new(->(_env) { [ 200, {}, [] ] })

    assert_includes logger.send(:started_request_message, request), '"/orders"'
  end
end
