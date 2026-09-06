# frozen_string_literal: true

require "test_helper"

class ActionLogTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @character = characters(:hernandes)
  end

  test "belongs to its user and polymorphic trackable record" do
    log = ActionLog.create!(user: @user, trackable: @character, action: "setup_illustration")

    assert_equal @user, log.user
    assert_equal @character, log.trackable
    assert_equal [ log ], @character.action_logs.for_action("setup_illustration").to_a
    assert_equal [ log ], @user.action_logs.for_action("setup_illustration").to_a
  end

  test "requires a user and trackable record" do
    log = ActionLog.new(action: "setup_illustration")

    assert_not log.valid?
    assert_includes log.errors[:user], "must exist"
    assert_includes log.errors[:trackable], "must exist"
  end

  test "records actions until the per-character trial limit is reached" do
    Character::TRIAL_CHARACTER_LIMIT.times { @character.record_action!("setup_illustration") }

    assert_equal Character::TRIAL_CHARACTER_LIMIT, @character.action_logs.for_action("setup_illustration").count
    assert_not @character.can_perform_action?("setup_illustration")
    assert_raises(RuntimeError, "Limit reached") { @character.record_action!("setup_illustration") }
  end

  test "enforces the trial limit across all of a user's characters" do
    characters = Array.new(8) do |index|
      Character.create!(user: @user, name: "Trial character #{index}")
    end
    characters.each do |character|
      Character::TRIAL_CHARACTER_LIMIT.times { character.record_action!("setup_illustration") }
    end

    another_character = Character.create!(user: @user, name: "One more character")

    assert_equal Character::TRIAL_USER_LIMIT, @user.action_logs.for_action("setup_illustration").count
    assert_not another_character.can_perform_action?("setup_illustration")
  end

  test "lets administrators bypass generation limits" do
    admin = User.create!(email: User::ADMINS.first)
    character = Character.create!(user: admin, name: "Admin character")
    Character::TRIAL_CHARACTER_LIMIT.times { character.record_action!("setup_illustration") }

    assert character.can_perform_action?("setup_illustration")
    assert_difference("ActionLog.count", 1) { character.record_action!("setup_illustration") }
  end
end
