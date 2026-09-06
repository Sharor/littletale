# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "counts GET page views and unique visitors per path" do
    first_visitor = Visitor.create!
    second_visitor = Visitor.create!
    Event.create!(visitor: first_visitor, path: "/books", method: "GET")
    Event.create!(visitor: first_visitor, path: "/books", method: "GET")
    Event.create!(visitor: second_visitor, path: "/books", method: "GET")
    Event.create!(visitor: second_visitor, path: "/books", method: "POST")

    assert_equal({ "/books" => 3 }, Event.page_views)
    assert_equal({ "/books" => 2 }, Event.unique_page_views)
  end
end
