require "test_helper"

class GenerateImageJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "constrained number of total generations when on trial" do
    @user = users(:two)
    @character = characters(:hernandes)
    @old = characters(:aske_cowboy)
    @character.user = @user
    populate_action_logs(@old, 9, @user)

    VCR.use_cassette("illustration", record: :once) do
      @character.setup_illustration
      perform_enqueued_jobs

      assert_equal(@character.illustration.original_image.blank?, true)
    end
  end

  test "allows generation when trial limit isn't reached" do
    @user = users(:two)
    @character = characters(:hernandes)
    @character.user = @user
    @old = characters(:aske_cowboy)
    populate_action_logs(@old, 4, @user)

    VCR.use_cassette("illustration", record: :once) do
      @character.setup_illustration
      perform_enqueued_jobs

      assert_equal(@character.illustration.original_image.present?, true)
    end
  end

  test "blocks after limit" do
    @user = users(:two)
    @one = characters(:hernandes)
    @one.user = @user
    populate_action_logs(@one, 7, @user)
    VCR.use_cassette("illustration", record: :once, allow_playback_repeats: :true) do
      @one.setup_illustration
      @one.setup_illustration
      @one.setup_illustration
      perform_enqueued_jobs

      @character = Character.new(name: @one.name, user: @one.user, age: @one.age, gender: @one.gender, ethnicity: @one.ethnicity,
                          hair_color: @one.hair_color, hair_style: @one.hair_style, eye_color: @one.eye_color)
      @character.save
      @character.setup_illustration

      assert_nil(@character&.illustration&.original_image&.blank?)
    end
  end

  private
  def populate_action_logs(character, amount, user)
    amount.times do |counter|
      character.action_logs.create!(action: "setup_illustration", user: user,
        created_at: "2025-05-0#{counter} 11:31:09.792278000 +0000", updated_at: "2025-05-0#{counter} 11:31:09.792278000 +0000")
      character.action_logs.create!(action: "setup_illustration", user: user,
        created_at: "2025-05-0#{counter} 11:31:09.792278000 +0000", updated_at: "2025-05-0#{counter} 11:31:09.792278000 +0000")
      character.action_logs.create!(action: "setup_illustration", user: user,
        created_at: "2025-05-0#{counter} 11:31:09.792278000 +0000", updated_at: "2025-05-0#{counter} 11:31:09.792278000 +0000")
    end
  end
end
