require "test_helper"
require "minitest/mock"

class BookWardrobePageImagesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  Book = Struct.new(:generation_attempt, :user_id) do
    def reload = self
  end
  WardrobePage = Struct.new(:book, :generation_attempt, :book_outfits, :ready, :required) do
    def wardrobe_required? = required
    def wardrobe_ready? = ready
    def wardrobe_instructions = "Authoritative saved wardrobe: Ada wears a blue swimsuit. Preserve identity, colors and equipment."
  end
  Attachment = Struct.new(:bytes) do
    def download = bytes
    def attached? = true
    def filename = "reference.png"
  end
  Outfit = Struct.new(:character_id, :description, :character_snapshot, :image)

  setup do
    @page = WardrobePage.new(Book.new(1, 7), 1,
      [Outfit.new(9, "blue swimsuit", { "name" => "Ada" }, Attachment.new("wardrobe pixels"))], true, true)
    @illustration = Illustration.new(original_description: "Ada in a red coat", generation_metadata: {})
    @illustration.define_singleton_method(:page) { @test_page }
    @illustration.instance_variable_set(:@test_page, @page)
    @illustration.define_singleton_method(:with_lock) { |&block| block.call }
    @illustration.define_singleton_method(:update!) { |attrs| assign_attributes(attrs); true }
  end

  test "saved wardrobe overrides raw scene clothing in final prompt" do
    assert_includes @illustration.specifications, @page.wardrobe_instructions
    assert_operator @illustration.specifications.index("Authoritative"), :>, @illustration.specifications.index("red coat")
  end

  test "ready saved wardrobes work after the original character becomes unavailable" do
    token = PageIllustrationGeneration.reserve!(@illustration, retrying: false)
    @page.book.define_singleton_method(:characters_ready_for_generation?) { false }
    @page.book.define_singleton_method(:characters) { [] }
    @page.book.define_singleton_method(:broadcast_generation_state) { }
    calls = 0
    @illustration.stub :gpt_image_1_edit, ->(_) { calls += 1; nil } do
      PageIllustrationGeneration.stub :enqueue!, false do
        PageIllustrationGeneration.perform!(@illustration, token)
      end
    end
    assert_equal 1, calls
  end

  test "image edit uploads saved outfit and removes temporary files" do
    paths = []
    image_api = Object.new
    image_api.define_singleton_method(:edit) do |parameters:|
      paths = parameters[:image].map(&:path)
      raise "wrong reference" unless parameters[:image].map(&:read) == ["wardrobe pixels"]
      { "paths" => paths }
    end
    client = Struct.new(:images).new(image_api)
    @illustration.stub :client, client do
      paths = @illustration.gpt_image_1_edit([]).fetch("paths")
    end
    assert_equal 1, paths.size
    paths.each { |path| assert_not File.exist?(path) }
  end

  test "a wardrobe book without selected characters generates without empty image references" do
    @page.book_outfits.clear
    images = Object.new
    images.define_singleton_method(:generate) { |parameters:| { "model" => parameters[:model] } }
    @illustration.stub :client, Struct.new(:images).new(images) do
      assert_equal "gpt-image-1", @illustration.gpt_image_1_edit([]).fetch("model")
    end
  end

  test "missing wardrobe prevents original reservation and direct paid image call" do
    @page.ready = false
    assert_nil PageIllustrationGeneration.reserve!(@illustration, retrying: false)
    assert_empty @illustration.generation_metadata
    @illustration.stub :client, -> { flunk "must not call image provider" } do
      assert_raises(RuntimeError) { @illustration.gpt_image_1_edit([]) }
    end
  end

  test "duplicate original delivery cannot spend another attempt after rejection" do
    @illustration.generation_metadata = { "page_generation" => {
      "status" => "rejected", "attempts" => [{ "number" => 1, "status" => "rejected" }] } }
    assert_nil PageIllustrationGeneration.reserve!(@illustration, retrying: false)
    assert_equal 1, PageIllustrationGeneration.attempts(@illustration).size
    assert PageIllustrationGeneration.reserve!(@illustration, retrying: true)
    assert_equal 2, PageIllustrationGeneration.attempts(@illustration).size
  end
  test "retry prompt preserves saved wardrobe with appropriate swimwear" do
    pages = []
    pages.define_singleton_method(:order) { |_| self }
    @page.book.define_singleton_method(:name) { "Swimming day" }
    @page.book.define_singleton_method(:plot) { "A pool adventure" }
    @page.book.define_singleton_method(:current_pages) { pages }
    @page.book.define_singleton_method(:characters) { [] }
    captured = nil
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      captured = parameters
      { "choices" => [{ "message" => { "content" => "Ada swims safely" } }] }
    end
    @illustration.stub(:client, client) { assert_equal "Ada swims safely", PageIllustrationPrompt.call(@illustration) }
    context = JSON.parse(captured[:messages].last[:content])
    assert_equal "blue swimsuit", context.fetch("wardrobe").first.fetch("description")
    assert_equal "Ada", context.fetch("wardrobe").first.fetch("character_snapshot").fetch("name")
    assert_includes captured[:messages].first[:content], "Preserve the saved clothing, colors and equipment"
    assert_not_includes captured[:messages].first[:content], "fully clothed"
  end

  test "wardrobe becoming unavailable after queueing prevents paid calls" do
    token = PageIllustrationGeneration.reserve!(@illustration, retrying: false)
    @page.ready = false
    @page.book.define_singleton_method(:characters_ready_for_generation?) { true }
    @page.book.define_singleton_method(:broadcast_generation_state) { }
    @illustration.stub :client, -> { flunk "must not call provider" } do
      PageIllustrationGeneration.perform!(@illustration, token)
    end
    assert_equal "cancelled", PageIllustrationGeneration.state(@illustration)["status"]
  end

  test "moderation records identify saved references and clean files" do
    paths = []
    image_api = Object.new
    image_api.define_singleton_method(:edit) do |parameters:|
      paths = parameters[:image].map(&:path)
      raise Faraday::BadRequestError.new("blocked", { status: 400, headers: {}, body: { "error" => { "code" => "moderation_blocked" } } })
    end
    @page.book.define_singleton_method(:record_generation_failure!) { |**_| }
    @illustration.stub :client, Struct.new(:images).new(image_api) do
      assert_nil @illustration.gpt_image_1_edit([])
    end
    references = @illustration.generation_metadata.fetch("request").fetch("reference_images")
    assert_equal 9, references.first.fetch("character_id")
    assert_equal "reference.png", references.first.fetch("image")
    paths.each { |path| assert_not File.exist?(path) }
  end

end
