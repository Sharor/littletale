require "test_helper"

class BookWardrobePlanTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(user: users(:one), name: "Bike and beach", total_pages: 2)
    @book.characters << characters(:hernandes)
    @story = [{ "story" => "We cycle", "image" => "Cycling" }, { "story" => "We swim", "image" => "Swimming" }]
    @plan = BookWardrobePlan.create!(book: @book, generation_attempt: 0, story: @story)
    @character_id = characters(:hernandes).id
  end

  test "accepts one outfit or explicit outfit transitions with full page coverage" do
    assert @plan.validate_outfits!({ "outfits" => [{ "character_id" => @character_id, "key" => "outdoor", "description" => "Blue jacket and helmet", "pages" => [1, 2] }] })
    assert @plan.validate_outfits!({ "outfits" => [
      { "character_id" => @character_id, "key" => "cycling", "description" => "Blue jacket and helmet", "pages" => [1] },
      { "character_id" => @character_id, "key" => "swimming", "description" => "Blue rash guard and swim shorts", "pages" => [2] }
    ] })
  end

  test "rejects missing overlapping and foreign character assignments before image requests" do
    base = { "character_id" => @character_id, "key" => "outdoor", "description" => "Blue jacket", "pages" => [1] }
    assert_raises(BookWardrobePlan::InvalidPlan) { @plan.validate_outfits!({ "outfits" => [base] }) }
    assert_raises(BookWardrobePlan::InvalidPlan) { @plan.validate_outfits!({ "outfits" => [base.merge("pages" => [1, 2]), base.merge("key" => "other", "pages" => [2])] }) }
    assert_raises(BookWardrobePlan::InvalidPlan) { @plan.validate_outfits!({ "outfits" => [base.merge("character_id" => -1, "pages" => [1, 2])] }) }
  end

  test "plans are unique per book attempt and do not affect old books" do
    assert_nil Book.create!(user: users(:one), name: "Legacy", total_pages: 1).current_wardrobe_plan
    assert_raises(ActiveRecord::RecordInvalid) { BookWardrobePlan.create!(book: @book, generation_attempt: 0) }
    assert BookWardrobePlan.create!(book: @book, generation_attempt: 1)
  end
end
