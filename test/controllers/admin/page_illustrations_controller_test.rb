require "test_helper"

class Admin::PageIllustrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @book = Book.create!(user: users(:one), name: "Incomplete", total_pages: 1, generation_status: :failed)
    @page = @book.pages.create!(text: "A park adventure", generation_attempt: @book.generation_attempt)
    @image = Illustration.create!(page: @page, original_description: "A park")
    @admin = users(:three)
    @admin.update!(admin: true)
  end

  test "only administrators can reserve a retry and duplicate clicks queue just one job" do
    sign_in users(:one)
    post regenerate_admin_page_illustration_path(@image)
    assert_response :forbidden
    sign_in @admin
    assert_enqueued_jobs 1, only: RegeneratePageIllustrationJob do
      2.times { post regenerate_admin_page_illustration_path(@image) }
    end
    assert_equal 2, PageIllustrationGeneration.attempts(@image.reload).length
  end

  test "controls give owners a limited retry and administrators an override route" do
    sign_in users(:one)
    get illustration_controls_page_path(@page)
    assert_response :success
    assert_select "form[action='#{regenerate_illustration_page_path(@page)}']"
    sign_in @admin
    get illustration_controls_page_path(@page)
    assert_response :success
    assert_select "form[action='#{regenerate_admin_page_illustration_path(@image)}']"
    sign_in users(:two)
    get illustration_controls_page_path(@page)
    assert_response :not_found
  end

  test "admins can retry beyond the automatic limit and duplicate clicks still queue one attempt" do
    @image.update!(generation_metadata: { "page_generation" => { "status" => "failed", "attempts" => [{}, {}, {}] } })
    sign_in @admin
    get illustration_controls_page_path(@page)
    assert_select "button", "Regenerate illustration"
    assert_enqueued_jobs 1, only: RegeneratePageIllustrationJob do
      2.times { post regenerate_admin_page_illustration_path(@image) }
    end
    assert_equal 4, PageIllustrationGeneration.attempts(@image.reload).length
    assert_equal @admin.id, PageIllustrationGeneration.attempts(@image).last["admin_id"]
  end

  test "an admin illustration override cannot bypass the owner's full trial book allowance" do
    owner = @book.user
    owner.update!(tier: "free")
    3.times do |number|
      held_book = owner.books.create!(name: "Held #{number}", total_pages: 1)
      TrialBookReservation.reserve_for!(held_book)
    end
    sign_in @admin

    assert_no_enqueued_jobs only: RegeneratePageIllustrationJob do
      post regenerate_admin_page_illustration_path(@image)
    end

    assert_equal 1, PageIllustrationGeneration.attempts(@image.reload).length
  end
end
