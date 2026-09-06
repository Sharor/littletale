# frozen_string_literal: true

require "test_helper"

class VisitorTest < ActiveSupport::TestCase
  test "calculates a visitor's total and average time on site from events" do
    visitor = Visitor.create!(user: users(:one))
    Event.create!(visitor: visitor, path: "/books", method: "GET", created_at: 5.minutes.ago)
    Event.create!(visitor: visitor, path: "/books/1", method: "GET", created_at: 3.minutes.ago)

    assert_in_delta 120, Visitor.total_time_on_site_for_visitor(visitor), 1
    assert_in_delta 120, Visitor.average_time_on_site_for_visitor(visitor), 1
    assert_in_delta 120, visitor.user.time_on_site, 1
  end

  test "deletes visitors older than a specified timestamp" do
    old_visitor = Visitor.create!(created_at: 2.days.ago)
    recent_visitor = Visitor.create!(created_at: 1.hour.ago)

    Visitor.delete_all_older_than(1.day.ago)

    assert_not Visitor.exists?(old_visitor.id)
    assert Visitor.exists?(recent_visitor.id)
  end
end
