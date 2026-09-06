# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "creates a free-tier user from a new Google identity" do
    identity = Struct.new(:info).new({ "email" => "new-parent@example.com", "name" => "New Parent" })

    assert_difference("User.count", 1) do
      user = User.from_omniauth(identity)

      assert_equal "new-parent@example.com", user.email
      assert_equal "New Parent", user.name
      assert_equal "free", user.tier
      assert_predicate user, :persisted?
    end
  end

  test "reuses an existing account for a returning Google identity" do
    existing_user = users(:one)
    identity = Struct.new(:info).new({ "email" => existing_user.email, "name" => "Changed Name" })

    assert_no_difference("User.count") do
      assert_equal existing_user, User.from_omniauth(identity)
    end

    assert_nil existing_user.reload.name
  end

  test "recognizes configured administrators only" do
    assert User.new(email: "davchristensen90@gmail.com").admin?
    assert_not User.new(email: "parent@example.com").admin?
  end
end
