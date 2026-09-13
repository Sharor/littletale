require "test_helper"
require "minitest/mock"

class BookWardrobePreparationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @book = Book.create!(user: users(:one), name: "Biking then swimming", plot: "Biking then swimming", total_pages: 2)
    @character = characters(:hernandes)
    @character.illustration.update!(original_image: File.open(file_fixture("character.png")))
    @character.update!(generation_status: :completed)
    @book.characters << @character
    @story = [{ "story" => "We ride bikes.", "image" => "Cycling" }, { "story" => "Then we swim.", "image" => "Swimming" }]
    @outfits = { "outfits" => [
      { "character_id" => @character.id, "key" => "cycling", "description" => "Red jacket and helmet", "pages" => [1] },
      { "character_id" => @character.id, "key" => "swimming", "description" => "Blue rash guard and swim shorts", "pages" => [2] }
    ] }
  end

  test "prepares once and waits for all outfit references before dispatching stable pages" do
    BookStoryGeneration.stub :call, @story do
      BookWardrobePlanner.stub :call, @outfits do
        assert_enqueued_jobs 2, only: GenerateBookOutfitJob do
          2.times { GenerateBookJob.perform_now(@book.id) }
        end
      end
    end
    plan = @book.current_wardrobe_plan
    assert_equal "preparing", plan.status
    assert_equal 2, plan.book_outfits.count
    assert_empty @book.pages
    source = @character.illustration.original_image.identifier
    BookWardrobeImageGeneration.stub :call, ->(_) { { io: StringIO.new(File.binread(file_fixture("character.png"))), filename: "outfit.png", content_type: "image/png" } } do
      first, second = plan.book_outfits.order(:id).to_a
      assert_no_enqueued_jobs(only: GeneratePageJob) { GenerateBookOutfitJob.perform_now(first.id) }
      assert_enqueued_jobs 2, only: GeneratePageJob do
        GenerateBookOutfitJob.perform_now(second.id)
      end
      assert_no_enqueued_jobs(only: GenerateBookOutfitJob) { GenerateBookOutfitJob.perform_now(first.id) }
    end
    assert_equal "ready", plan.reload.status
    assert_equal [1, 2], @book.current_pages.pluck(:story_position)
    assert_equal ["cycling"], @book.current_pages.first.book_outfits.map(&:outfit_key)
    assert_equal ["swimming"], @book.current_pages.last.book_outfits.map(&:outfit_key)
    assert_equal source, @character.illustration.reload.original_image.identifier
  end

  test "invalid wardrobe never starts reference or page generation" do
    BookStoryGeneration.stub :call, @story do
      BookWardrobePlanner.stub :call, { "outfits" => [] } do
        assert_no_enqueued_jobs(only: [GenerateBookOutfitJob, GeneratePageJob]) { GenerateBookJob.perform_now(@book.id) }
      end
    end
    assert @book.reload.failed?
    assert_equal "wardrobe_preparation_failed", @book.generation_failure["type"]
  end

  test "story and wardrobe retain saved roles from before a character edit" do
    @character.update!(roles: [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ])
    requests = []
    story = @story
    outfits = @outfits
    character = @character
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      requests << parameters
      character.update!(roles: [ "Supporting" ]) if requests.length == 1
      { "choices" => [ { "message" => { "content" => (requests.length == 1 ? story : outfits).to_json } } ] }
    end

    OpenAI::Client.stub :new, client do
      GenerateBookJob.perform_now(@book.id)
      GenerateBookJob.perform_now(@book.id)
    end

    assert_equal 2, requests.size
    requests.each do |request|
      metadata = JSON.parse(request.fetch(:messages).last.fetch(:content)).fetch("characters").sole
      assert_equal [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ], metadata.fetch("roles")
    end
    assert_includes requests.first.fetch(:messages).first.fetch(:content), "Hero, Villain and Supporting"
    plan = @book.current_wardrobe_plan
    assert_equal "preparing", plan.status
    assert_equal [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ], plan.character_snapshots.sole.fetch("roles")
    plan.book_outfits.each do |outfit|
      assert_equal [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ], outfit.character_snapshot.fetch("roles")
    end
    assert_equal [ "Supporting" ], @character.reload.roles
  end

  test "provider credit exhaustion is explained and recorded without retrying generation" do
    error = Faraday::TooManyRequestsError.new("quota exhausted", status: 429,
      headers: { "x-request-id" => "req_quota" },
      body: { "error" => { "code" => "credit_balance_exhausted", "type" => "insufficient_quota" } })
    calls = 0
    BookStoryGeneration.stub :call, ->(*) { calls += 1; raise error } do
      assert_no_enqueued_jobs(only: [GenerateBookOutfitJob, GeneratePageJob]) { GenerateBookJob.perform_now(@book.id) }
    end
    assert_equal 1, calls
    failure = @book.reload.generation_failure
    assert_equal "wardrobe_provider_quota", failure["type"]
    assert_includes failure["message"], "credit or usage limit"
    assert_equal "credit_balance_exhausted", failure.dig("metadata", "code")
    assert_equal "req_quota", failure.dig("metadata", "request_id")
    assert_equal "story", failure.dig("metadata", "stage")
  end

  test "source pixels and character identity are frozen before planning calls" do
    original = @character.illustration.original_image.read
    original_name = @character.name
    replacement = Tempfile.new(["changed-character", ".png"])
    replacement.binmode
    replacement.write(original + "changed".b)
    replacement.rewind
    BookStoryGeneration.stub :call, @story do
      BookWardrobePlanner.stub :call, ->(*) {
        @character.update!(name: "Changed character")
        @character.illustration.update!(original_image: replacement)
        @outfits
      } do
        GenerateBookJob.perform_now(@book.id)
      end
    end
    outfit = @book.current_wardrobe_plan.book_outfits.first
    assert_equal original, outfit.source_image.download
    assert_equal original_name, outfit.character_snapshot["name"]
  ensure
    replacement&.close!
  end

  test "deleting a wardrobe book keeps original characters intact" do
    plan = BookWardrobePlan.create!(book: @book, generation_attempt: 0)
    @book.pages.create!(book_wardrobe_plan: plan, story_position: 1, text: "A page")
    @book.destroy!
    assert Character.exists?(@character.id)
    assert_not BookWardrobePlan.exists?(plan.id)
  end

  test "duplicate book jobs keep completed wardrobes after an original character edit" do
    plan = BookWardrobePlan.create!(book: @book, generation_attempt: 0, status: "ready", story: @story,
      character_snapshots: [{ "id" => @character.id }])
    outfit = plan.book_outfits.create!(character_id: @character.id, outfit_key: "outdoors",
      description: "Outdoor clothes", page_numbers: [1, 2], status: "ready")
    outfit.image.attach(io: File.open(file_fixture("character.png")), filename: "outfit.png", content_type: "image/png")
    BookWardrobeDispatch.call(plan)
    @book.current_pages.each { |page| page.illustration.update!(original_image: File.open(file_fixture("character.png"))) }
    @book.update!(generation_status: :completed)
    @character.update!(generation_status: :pending)
    BookStoryGeneration.stub :call, ->(*) { flunk "Reuse the prepared story" } do
      assert_no_enqueued_jobs(only: [GenerateBookOutfitJob, GeneratePageJob]) { GenerateBookJob.perform_now(@book.id) }
    end
    assert @book.reload.completed?
    assert_equal 1, @book.book_wardrobe_plans.count
  end

  test "a rejected outfit stops page generation and duplicate delivery never repeats a paid call" do
    BookStoryGeneration.stub :call, @story do
      BookWardrobePlanner.stub :call, @outfits do
        GenerateBookJob.perform_now(@book.id)
      end
    end
    outfit = @book.current_wardrobe_plan.book_outfits.first
    calls = 0
    BookWardrobeImageGeneration.stub :call, ->(_) { calls += 1; raise BookWardrobeImageGeneration::Refused.new(public_reason: "Outfit declined", metadata: { "code" => "moderation_blocked" }) } do
      assert_no_enqueued_jobs(only: GeneratePageJob) { 2.times { GenerateBookOutfitJob.perform_now(outfit.id) } }
    end
    assert_equal 1, calls
    assert_equal "rejected", outfit.reload.status
    assert @book.reload.failed?
  end

  test "outfits from superseded generation cannot make new pages" do
    BookStoryGeneration.stub :call, @story do
      BookWardrobePlanner.stub :call, @outfits do
        GenerateBookJob.perform_now(@book.id)
      end
    end
    outfit = @book.current_wardrobe_plan.book_outfits.first
    @book.prepare_for_regeneration!
    BookWardrobeImageGeneration.stub :call, ->(_) { flunk "Do not spend on superseded outfits" } do
      GenerateBookOutfitJob.perform_now(outfit.id)
    end
    assert_empty @book.current_pages
    assert @book.reload.pending?
  end
end
