# frozen_string_literal: true

require "test_helper"

class CategorizeBookJobTest < ActiveJob::TestCase
  test "categorizes a completed book asynchronously" do
    book = Book.create!(user: users(:one), name: "Finished tale", total_pages: 1)
    book.update_columns(generation_status: Book.generation_statuses.fetch("completed"))
    book.pages.create!(text: "A pirate crossed the sea.", generation_attempt: book.generation_attempt)
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      { "choices" => [ { "message" => { "content" => { categories: [ "Pirates", "Sea & Maritime" ] }.to_json } } ] }
    end

    OpenAI::Client.stub(:new, client) do
      CategorizeBookJob.perform_now(book.id, book.generation_attempt)
    end

    assert_equal [ "Pirates", "Sea & Maritime" ], book.reload.categories
  end

  test "ignores a job for an obsolete generation attempt" do
    book = Book.create!(user: users(:one), name: "Regenerated tale", total_pages: 1, generation_status: :completed)
    old_attempt = book.generation_attempt
    book.update_columns(generation_attempt: old_attempt + 1,
      generation_status: Book.generation_statuses.fetch("in_progress"))
    client = Object.new
    client.define_singleton_method(:chat) { |parameters:| flunk("obsolete job called OpenAI") }

    OpenAI::Client.stub(:new, client) do
      CategorizeBookJob.perform_now(book.id, old_attempt)
    end

    assert_empty book.reload.categories
  end
  test "does not call OpenAI when categories were already assigned" do
    book = Book.create!(user: users(:one), name: "Manual tale", total_pages: 1,
      generation_status: :completed, categories: [ "Friendship" ])
    client = Object.new
    client.define_singleton_method(:chat) { |parameters:| flunk("categorized book called OpenAI") }

    OpenAI::Client.stub(:new, client) do
      CategorizeBookJob.perform_now(book.id, book.generation_attempt)
    end

    assert_equal [ "Friendship" ], book.reload.categories
  end

  test "recovers completed books whose initial enqueue failed" do
    missing = Book.create!(user: users(:one), name: "Missing handoff", total_pages: 1)
    missing.update_columns(generation_status: Book.generation_statuses.fetch("completed"))
    queued = Book.create!(user: users(:one), name: "Queued handoff", total_pages: 1)
    queued.update_columns(generation_status: Book.generation_statuses.fetch("completed"),
      categorization_enqueued_at: Time.current)
    categorized = Book.create!(user: users(:one), name: "Manual categories", total_pages: 1,
      categories: [ "Adventure" ])
    categorized.update_columns(generation_status: Book.generation_statuses.fetch("completed"))

    assert_enqueued_with(job: CategorizeBookJob, args: [ missing.id, missing.generation_attempt ]) do
      CategorizeBookJob.enqueue_missing
    end

    assert_not_nil missing.reload.categorization_enqueued_at
    assert_not_nil queued.reload.categorization_enqueued_at
    assert_nil categorized.reload.categorization_enqueued_at
  end

  test "discards jobs for deleted books without retrying" do
    assert_no_enqueued_jobs do
      CategorizeBookJob.perform_now(-1, 0)
    end
  end
end
