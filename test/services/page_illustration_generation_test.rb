require "test_helper"
require "minitest/mock"

class PageIllustrationGenerationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @book = Book.create!(user: users(:one), name: "Biking", total_pages: 1, generation_status: :failed)
    @page = @book.pages.create!(text: "We cycle through the park.", generation_attempt: @book.generation_attempt)
    @image = Illustration.create!(page: @page, original_description: "Cycling in pyjamas")
  end

  test "legacy original counts and duplicate reservations cannot spend another retry" do
    token = PageIllustrationGeneration.reserve!(@image, retrying: true)
    assert token
    assert_nil PageIllustrationGeneration.reserve!(@image.reload, retrying: true)
    assert_equal 2, @image.reload.generation_metadata.dig("page_generation", "attempts").length
  end

  test "only explicit admin retries bypass the cap without extending automatic retries" do
    @image.update!(generation_metadata: { "page_generation" => { "status" => "failed", "attempts" => [{}, {}, {}] } })
    assert_nil PageIllustrationGeneration.reserve!(@image, retrying: true, admin: users(:one))
    admin = users(:three)
    admin.update!(email: User::ADMINS.first)

    2.times do
      assert PageIllustrationGeneration.reserve!(@image, retrying: true, admin: admin)
      PageIllustrationGeneration.finish!(@image, "rejected")
      assert_not PageIllustrationGeneration.enqueue!(@image)
    end
    assert_equal 5, PageIllustrationGeneration.attempts(@image.reload).length
  end

  test "an unsuccessful enqueue releases its reservation for an admin retry" do
    [false, ->(*) { raise "queue unavailable" }].each do |result|
      RegeneratePageIllustrationJob.stub :perform_later, result do
        assert_not PageIllustrationGeneration.enqueue!(@image)
      end
      assert PageIllustrationGeneration.available?(@image.reload)
      assert_equal 1, PageIllustrationGeneration.attempts(@image).length
    end
  end

  test "a page finishing after whole-book regeneration cannot complete the new attempt" do
    token = PageIllustrationGeneration.reserve!(@image, retrying: false)
    @image.stub :gpt_image_1_edit, ->(_) {
      @book.prepare_for_regeneration!
      { "data" => [] }
    } do
      @image.stub :extract_image_base64, ->(_) { @image.update!(original_image: File.open(file_fixture("character.png"))) } do
        PageIllustrationGeneration.perform!(@image, token)
      end
    end
    assert_equal 1, @book.reload.generation_attempt
    assert @book.pending?
  end

  test "a page failing after whole-book regeneration cannot fail the new attempt" do
    token = PageIllustrationGeneration.reserve!(@image, retrying: false)
    @image.stub :gpt_image_1_edit, ->(_) {
      @book.prepare_for_regeneration!
      raise Timeout::Error
    } do
      PageIllustrationGeneration.perform!(@image, token)
    end
    assert @book.reload.pending?
    assert_empty @book.generation_failure
  end

  test "a revised prompt is persisted and a successful retry completes the existing book" do
    token = PageIllustrationGeneration.reserve!(@image, retrying: true)
    PageIllustrationPrompt.stub :call, "Children cycling in outdoor clothes and helmets" do
      @image.stub :gpt_image_1_edit, { "data" => [] } do
        @image.stub :extract_image_base64, ->(_) { @image.update!(original_image: File.open(file_fixture("character.png"))) } do
          PageIllustrationGeneration.perform!(@image, token)
          PageIllustrationGeneration.perform!(@image, token)
        end
      end
    end
    assert_equal 1, @book.pages.count
    assert @book.reload.completed?
    assert_equal "succeeded", @image.reload.generation_metadata.dig("page_generation", "attempts", -1, "status")
    assert_includes @image.original_description, "helmets"
  end

  test "rejections automatically retry with a new prompt but never exceed three total attempts" do
    calls = 0
    PageIllustrationPrompt.stub :call, ->(_) { "Safe outdoor scene #{calls}" } do
      @image.stub :gpt_image_1_edit, ->(_) { calls += 1; nil } do
        3.times do |index|
          token = PageIllustrationGeneration.reserve!(@image, retrying: index > 0)
          # Automatic retry reserves the next attempt, so consume that queued token instead.
          token ||= @image.reload.generation_metadata.dig("page_generation", "token")
          PageIllustrationGeneration.perform!(@image, token)
        end
      end
    end
    assert_equal 3, calls
    assert_nil PageIllustrationGeneration.reserve!(@image, retrying: true)
    assert_equal 3, @image.reload.generation_metadata.dig("page_generation", "attempts").length
  end

  test "successful images and superseded pages cannot be retried" do
    @image.update!(original_image: File.open(file_fixture("character.png")))
    assert_nil PageIllustrationGeneration.reserve!(@image, retrying: true)
    @image.remove_original_image!
    @image.save!
    @book.update_column(:generation_attempt, 1)
    assert_nil PageIllustrationGeneration.reserve!(@image, retrying: true)
  end

  test "an uncertain provider failure is recorded without automatic paid retries" do
    token = PageIllustrationGeneration.reserve!(@image, retrying: false)
    @image.stub :gpt_image_1_edit, ->(_) { raise Timeout::Error, "uncertain response" } do
      assert_no_enqueued_jobs(only: RegeneratePageIllustrationJob) do
        PageIllustrationGeneration.perform!(@image, token)
      end
    end
    assert_equal "failed", @image.reload.generation_metadata.dig("page_generation", "attempts", -1, "status")
    assert @book.reload.failed?
  end
end
