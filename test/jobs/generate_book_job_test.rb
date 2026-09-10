# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class GenerateBookJobTest < ActiveJob::TestCase
  test "orchestrates story generation without performing external work itself" do
    book = Book.create!(user: users(:one), name: "New wardrobe book", total_pages: 1)
    calls = []
    BookWardrobePreparation.stub :call, ->(plan) { calls << plan.id } do
      2.times { GenerateBookJob.perform_now(book.id) }
    end
    assert_equal 1, book.book_wardrobe_plans.count
    assert_equal [book.current_wardrobe_plan.id] * 2, calls
    assert book.reload.in_progress?
  end

  test "initializes and saves the structured story generator" do
    book = Struct.new(:plot).new("A moonlit adventure")
    chatgpt = Minitest::Mock.new
    chatgpt.expect :generate_v2, true
    chatgpt.expect :save, true
    job = GenerateBookJob.new

    Chatgpt.stub :new, ->(attributes) {
      assert_equal({ book: book, prompt: "A moonlit adventure" }, attributes)
      chatgpt
    } do
      job.initialize_AI(book)
    end

    chatgpt.verify
  end

  test "enqueues one page job for each generated story section" do
    book = Struct.new(:id, :generation_attempt).new(17, 0)
    story = [ { "story" => "First" }, { "story" => "Second" } ]

    assert_enqueued_jobs 2, only: GeneratePageJob do
      GenerateBookJob.new.image_generation(story, book)
    end

    assert_equal story, enqueued_jobs.last(2).map { |job| job[:args].second.slice("story") }
    assert_equal [ 0, 0 ], enqueued_jobs.last(2).map { |job| job[:args].third }
  end

  test "waits for images to become available and reloads pages between attempts" do
    pages = Minitest::Mock.new
    pages.expect :all?, false
    pages.expect :reload, pages
    pages.expect :all?, true
    book = Minitest::Mock.new
    book.expect :pages, pages
    book.expect :pages, pages
    book.expect :pages, pages
    waits = []
    job = GenerateBookJob.new

    job.stub :sleep, ->(seconds) { waits << seconds } do
      job.ensure_storage_cache_consistency(book)
    end

    assert_equal [ 1 ], waits
    book.verify
    pages.verify
  end

  test "marks a fully illustrated book complete and broadcasts its state" do
    book = Book.new(user: users(:one), name: "Finished", total_pages: 1)
    illustration = Struct.new(:original_image).new(Object.new)
    page = Struct.new(:illustration).new(illustration)
    broadcasts = []
    job = GenerateBookJob.new

    book.stub :pages, [ page ] do
      book.stub :completed!, true do
        book.stub :broadcast_replace_to, ->(*args, **options) { broadcasts << [ args, options ] } do
          job.broadcast_changes_swap_loadscreen(book)
        end
      end
    end

    assert_equal 1, broadcasts.size
    assert_equal book, broadcasts.first.first.first
    assert_equal "books/book_state", broadcasts.first.last[:partial]
  end
end
