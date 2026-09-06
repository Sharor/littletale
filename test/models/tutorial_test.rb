require "test_helper"

class TutorialTest < ActiveSupport::TestCase
  test "belongs to its user" do
    tutorial = tutorials(:one)

    assert_equal users(:one), tutorial.user
  end

  test "requires a user" do
    tutorial = Tutorial.new(eula: false, terms: false, tutorial_complete: false)

    assert_not tutorial.valid?
    assert_includes tutorial.errors[:user], "must exist"
  end
end
