# frozen_string_literal: true

class PrintOrder < ApplicationRecord
  class IneligibleBook < StandardError; end

  POD_PACKAGE_ID = "0500X0800.FC.PRE.SS.060UW444.GXX".freeze

  belongs_to :user
  belongs_to :source_book, class_name: "Book", optional: true
  has_many :print_order_pages, -> { order(:position) }, dependent: :destroy, inverse_of: :print_order
  has_one_attached :interior_pdf
  has_one_attached :cover_pdf

  validates :title, :language, :workflow_state, :pod_package_id, presence: true
  validates :step, numericality: { only_integer: true, in: 1..3 }
  validates :content_revision, numericality: { only_integer: true, greater_than: 0 }
  validates :pod_package_id, inclusion: { in: [ POD_PACKAGE_ID ] }

  def self.start_for!(user:, book:)
    pages = eligible_pages(user:, book:)
    order = nil

    transaction do
      order = user.print_orders.create!(
        source_book: book,
        title: book.name,
        language: book.language,
        pod_package_id: POD_PACKAGE_ID
      )
      pages.each_with_index do |page, index|
        retained_page = order.print_order_pages.create!(position: index + 1, text: page.text.to_s)
        retained_page.copy_image_from!(page.illustration.original_image)
      end
    end

    order
  rescue StandardError
    order&.destroy! if order&.persisted?
    raise
  end

  def current_pages
    print_order_pages
  end

  def gift_preparable?
    false
  end

  def self.eligible_pages(user:, book:)
    pages = book.current_pages.includes(:illustration).to_a
    eligible = user.admin? && book.user_id == user.id && book.completed? && pages.length == book.total_pages &&
      pages.any? && pages.all? { |page| page.text.present? && page.illustration&.original_image&.present? }
    raise IneligibleBook, "Choose one of your completed, fully illustrated books" unless eligible

    pages
  end
  private_class_method :eligible_pages
end
