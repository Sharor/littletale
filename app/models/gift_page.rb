# frozen_string_literal: true

class GiftPage < ApplicationRecord
  belongs_to :book_gift, inverse_of: :gift_pages
  has_one_attached :image

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :book_gift_id }
  validates :text, presence: true

  def copy_image_from!(uploader)
    return unless uploader.present?

    bytes = uploader.file.read
    image.attach(
      io: StringIO.new(bytes),
      filename: uploader.filename.presence || "gift-page-#{position}.png",
      content_type: uploader.file.content_type
    )
  end
end
