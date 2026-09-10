require "test_helper"

class ImageUploaderTest < ActiveSupport::TestCase
  test "removing the same fixture image in another process preserves this process image" do
    model = Illustration.new(id: 987654321)
    uploader = ImageUploader.new(model, :original_image)
    File.open(file_fixture("character.png")) { |file| uploader.store!(file) }
    image_path = uploader.path

    child = fork do
      other = ImageUploader.new(model, :original_image)
      File.open(file_fixture("character.png")) { |file| other.store!(file) }
      other.remove!
      exit! 0
    end
    Process.wait(child)
    assert_predicate $?, :success?
    assert File.exist?(image_path), "Another test process removed this worker's character image"
  ensure
    uploader&.remove!
  end
end
