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

  test "Google signup cannot grant admin access from identity data" do
    identity = Struct.new(:info).new({ "email" => "davchristensen90@gmail.com",
      "name" => "New User", "admin" => true })
    user = User.from_omniauth(identity)
    assert_equal false, user.reload.admin
    assert user.admin?
  end

  test "records Google verification for the account email" do
    identity = Struct.new(:provider, :info, :extra).new(
      "google_oauth2",
      { "email" => "verified@gmail.com", "name" => "Verified Reader" },
      { "raw_info" => { "email_verified" => true } }
    )

    user = User.from_omniauth(identity)

    assert_not_nil user.google_email_verified_at
    assert_predicate user, :google_email_verified?
  end

  test "uses the Microsoft principal name when the mail field is absent" do
    identity = Struct.new(:provider, :info, :extra).new(
      "microsoft_v2_auth",
      { "email" => nil, "name" => "Outlook Reader" },
      { "raw_info" => { "userPrincipalName" => "reader@outlook.com" } }
    )

    assert_difference("User.count", 1) do
      user = User.from_omniauth(identity)

      assert_equal "reader@outlook.com", user.email
      assert_predicate user, :persisted?
    end
  end

  test "reuses an existing account when Microsoft returns different email casing" do
    existing_user = User.create!(email: "reader@outlook.com")
    identity = Struct.new(:provider, :info, :extra).new(
      "microsoft_v2_auth",
      { "email" => " READER@OUTLOOK.COM ", "name" => "Outlook Reader" },
      { "raw_info" => {} }
    )

    assert_no_difference("User.count") do
      assert_equal existing_user, User.from_omniauth(identity)
    end
  end

  test "does not record Google verification from a Microsoft identity" do
    identity = Struct.new(:provider, :info, :extra).new(
      "microsoft_v2_auth",
      { "email" => "reader@outlook.com", "name" => "Outlook Reader" },
      { "raw_info" => { "email_verified" => true } }
    )

    user = User.from_omniauth(identity)

    assert_nil user.google_email_verified_at
  end

  test "admin access requires an explicit grant and can be revoked" do
    user = User.create!(email: "explicit-admin@example.com", admin: true)
    assert user.reload.admin?
    user.update!(admin: false)
    assert_not user.reload.admin?
  end

  test "legacy null admin values do not grant access" do
    assert User.new(email: "davchristensen90@gmail.com", admin: nil).admin?
  end
end
