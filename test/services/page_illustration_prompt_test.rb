require "test_helper"
require "minitest/mock"

class PageIllustrationPromptTest < ActiveSupport::TestCase
  test "revision includes page context and preserves character ages with appropriate clothing" do
    book = Book.create!(user: users(:one), name: "Cycling", plot: "A family cycling trip", total_pages: 2,
      art_style: "colored_pencil")
    book.characters << characters(:hernandes)
    characters(:hernandes).update!(roles: [ "Father", "Freckles", "Supporting" ])
    book.pages.create!(text: "We put on our helmets.")
    page = book.pages.create!(text: "We cycle along a quiet path.")
    illustration = Illustration.create!(page: page, original_description: "Children in pyjamas cycling")
    params = nil
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      params = parameters
      { "choices" => [{ "message" => { "content" => "Children cycling in jackets and helmets" } }] }
    end
    illustration.stub :client, client do
      assert_equal "Children cycling in jackets and helmets", PageIllustrationPrompt.call(illustration)
    end
    context = JSON.parse(params[:messages].last[:content])
    assert_equal page.id, context["page_id"]
    assert_equal 2, context["pages"].length
    assert_equal characters(:hernandes).age, context["characters"].first["age"]
    assert_equal [ "Father", "Freckles", "Supporting" ], context["characters"].first["roles"]
    assert_equal "Green", context["characters"].first["eye_color"]
    assert_includes context.fetch("art_style"), "visible pencil grain"
    assert_includes params[:messages].first[:content], "clothing appropriate to the setting"
    assert_includes params[:messages].first[:content], "art_style"
    assert_includes params[:messages].first[:content], "rather than disguising it or evading safety checks"
  end

  test "a prompt model refusal stops image generation" do
    book = Book.create!(user: users(:one), name: "Refused scene", total_pages: 1)
    page = book.pages.create!(text: "A scene")
    illustration = Illustration.create!(page: page)
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      { "choices" => [{ "message" => { "refusal" => "Cannot provide a safe depiction" } }] }
    end
    illustration.stub :client, client do
      assert_raises(RuntimeError) { PageIllustrationPrompt.call(illustration) }
    end
  end
end
