# frozen_string_literal: true

require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "requires a name and a positive page count" do
    book = Book.new(user: users(:one), total_pages: 0)

    assert_not book.valid?
    assert_includes book.errors[:name], "can't be blank"
    assert_includes book.errors[:total_pages], "must be greater than 0"
  end

  test "enforces the user's tier page limit" do
    user = users(:one)
    user.update!(tier: "free")
    book = Book.new(user: user, name: "Long tale", total_pages: 6)

    assert_not book.valid?
    assert_includes book.errors[:total_pages], "cannot exceed 5 pages for the Free tier"
  end

  test "maps completed page counts to construction levels" do
    book = Book.new(user: users(:one), name: "Tale", total_pages: 5)

    assert_equal 1, book.construction_level
  end
end
