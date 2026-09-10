require "test_helper"
require "minitest/mock"

class RecoverBookWardrobesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "recovers persisted reference bytes without calling the image provider again" do
    book = Book.create!(user: users(:one), name: "Recovery", total_pages: 1, generation_status: :in_progress)
    plan = BookWardrobePlan.create!(book: book, generation_attempt: 0, status: "preparing",
      story: [{ "story" => "Cycling", "image" => "A cycling scene" }], character_snapshots: [{ "id" => 1 }])
    outfit = plan.book_outfits.create!(character_id: 1, outfit_key: "cycling", description: "Helmet and jacket", page_numbers: [1], status: "generating", claimed_at: 2.hours.ago)
    outfit.image.attach(io: File.open(file_fixture("character.png")), filename: "outfit.png", content_type: "image/png")
    BookWardrobeImageGeneration.stub :call, ->(_) { flunk "Reuse the saved result" } do
      RecoverBookWardrobesJob.perform_now
    end
    assert_equal "ready", outfit.reload.status
    assert plan.reload.ready?
    assert_equal 1, book.pages.count
  end

  test "interrupted paid requests become unknown and do not retry" do
    book = Book.create!(user: users(:one), name: "Unknown", total_pages: 1, generation_status: :in_progress)
    plan = BookWardrobePlan.create!(book: book, generation_attempt: 0, status: "preparing")
    outfit = plan.book_outfits.create!(character_id: 1, outfit_key: "cycling", description: "Helmet", status: "generating", claimed_at: 2.hours.ago)
    assert_no_enqueued_jobs(only: GenerateBookOutfitJob) { RecoverBookWardrobesJob.perform_now }
    assert_equal "outcome_unknown", outfit.reload.status
    assert book.reload.failed?
  end
end
