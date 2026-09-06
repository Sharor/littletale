# frozen_string_literal: true

require "test_helper"

class VisitorTrackingTest < ActionDispatch::IntegrationTest
  teardown { Current.reset }

  test "creates one visitor per browser session and filters recorded parameters" do
    assert_difference([ "Visitor.count", "Event.count" ], 1) do
      get "/", params: { chapter: "forest", password: "do-not-store" }
    end

    event = Event.order(:id).last
    visitor_id = event.visitor_id

    assert_equal "/", event.path
    assert_equal "GET", event.method
    assert_equal "forest", JSON.parse(event.params).fetch("chapter")
    assert_equal "[FILTERED]", JSON.parse(event.params).fetch("password")

    assert_no_difference("Visitor.count") { get "/" }
    assert_equal visitor_id, Event.order(:id).last.visitor_id
  end
end
