# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class GeneratePageJobTest < ActiveJob::TestCase
  self.fixture_table_names = []

  test "delegates page creation to the requested book" do
    book_id = 29
    page_data = { "story" => "A new chapter", "image" => "A lighthouse" }
    book = Minitest::Mock.new
    book.expect :generation_attempt, 0
    book.expect :generation_attempt, 0
    book.expect :create_pages_from_answer, true, [ page_data ], attempt: 0
    book.expect :refresh_generation_status!, true, [], attempt: 0

    Book.stub :find, ->(id) { assert_equal book_id, id; book } do
      GeneratePageJob.perform_now(book_id, page_data)
    end

    book.verify
  end
end
