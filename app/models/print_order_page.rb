# frozen_string_literal: true

class PrintOrderPage < ApplicationRecord
  belongs_to :print_order, inverse_of: :print_order_pages
  has_one_attached :image

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :print_order_id }
  validates :text, presence: true

  def copy_image_from!(uploader)
    bytes = uploader.file.read
    image.attach(
      io: StringIO.new(bytes),
      filename: uploader.filename.presence || "print-order-page-#{position}.png",
      content_type: uploader.file.content_type
    )
  end

  def illustration
    self
  end

  def original_image
    image
  end
end
