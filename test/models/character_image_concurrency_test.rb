require "test_helper"

class CharacterImageConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_table_names = []

  setup do
    @user = User.create!(email: "screening-#{SecureRandom.hex(8)}@example.test")
    @character = @user.characters.create!(name: "Concurrent", age: 8, gender: "Girl", ethnicity: "Asian",
      eye_color: "Brown", hair_color: "Black", hair_style: "Long")
  end

  teardown do
    @user.characters.update_all(current_image_request_id: nil)
    ids = @user.character_image_requests.pluck(:id)
    CharacterImageDecision.where(user_id: @user.id).delete_all
    CharacterImageGenerationAttempt.where(request_id: ids).delete_all
    ActionLog.where(user_id: @user.id).delete_all
    CharacterImageRequest.where(user_id: @user.id).delete_all
    CharacterImageAssessment.where(user_id: @user.id).delete_all
    @user.characters.destroy_all
    @user.destroy!
  end

  test "concurrent identical submissions share one assessment and request" do
    results = concurrently(2) { CharacterImageRequest.submit!(Character.find(@character.id)).id }
    assert_equal 1, results.uniq.size
    assert_equal 1, @user.character_image_assessments.count
    assert_equal 1, @user.character_image_requests.count
    assert_equal 1, @user.action_logs.count
  end

  test "concurrent generation reservations cannot exceed the remaining user allowance" do
    other = @character.dup
    other.name = "Second"
    other.hair_color = "Red"
    other.save!
    filler = @user.characters.create!(name: "Previous usage")
    (Character::TRIAL_USER_LIMIT - 1).times { @user.action_logs.create!(action: "setup_illustration", trackable: filler) }
    requests = [ @character, other ].map { |character| CharacterImageRequest.submit!(character) }
    requests.each { |request| request.assessment.update!(status: "approved") }
    concurrently(2) { |index| CharacterImageRequest.find(requests[index].id).enqueue_generation! }
    assert_equal Character::TRIAL_USER_LIMIT, @user.action_logs.for_action("setup_illustration").count
    assert_equal 1, CharacterImageGenerationAttempt.where(request_id: requests.map(&:id)).count
  end

  private

  def concurrently(count)
    ready = Queue.new
    start = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield index
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    threads.map(&:value)
  end
end
