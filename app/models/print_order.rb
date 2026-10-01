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
  with_options on: :delivery do
    validates :recipient_name, :street1, :city, :postcode, :country_code, :recipient_email, :phone_number,
      presence: true
    validates :country_code, length: { is: 2 }
    validates :recipient_email, format: { with: URI::MailTo::EMAIL_REGEXP }
    validate :state_code_required_for_selected_country
  end

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

  def name
    title
  end

  def gift_preparable?
    false
  end

  def self.eligible_book?(user:, book:)
    eligible_pages(user:, book:)
    true
  rescue IneligibleBook
    false
  end

  def save_delivery_address(attributes)
    assign_attributes(attributes)
    normalize_delivery_address
    return false unless valid?(:delivery)

    self.step = 3
    self.shipping_option = nil
    self.shipping_options = []
    self.quote = {}
    self.quote_revision = nil
    self.quoted_at = nil
    save!
  end

  def address_complete?
    valid?(:delivery)
  end

  def artifacts_current?
    artifacts_revision == content_revision && interior_pdf.attached? && cover_pdf.attached?
  end

  def enqueue_preparation!
    with_lock do
      return true if artifacts_current?
      return false unless address_complete?

      update!(workflow_state: "preparing", failure_message: nil)
      job = PreparePrintOrderJob.perform_later(id, content_revision)
      return true if job&.successfully_enqueued?

      update!(workflow_state: "failed", failure_message: I18n.t("print_orders.errors.preparation_queue"))
      false
    end
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    update_columns(workflow_state: "failed", failure_message: I18n.t("print_orders.errors.preparation_queue"))
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

  private

  def normalize_delivery_address
    %i[recipient_name street1 street2 city postcode state_code recipient_email phone_number].each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
    self.country_code = country_code.to_s.strip.upcase.presence
  end

  def state_code_required_for_selected_country
    return unless country_code.in?(%w[US CA AU]) && state_code.blank?

    errors.add(:state_code, :blank)
  end
end
