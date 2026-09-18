# frozen_string_literal: true

class BookCredit < ApplicationRecord
  class LimitReached < StandardError; end

  belongs_to :user
  belongs_to :book_purchase
  has_many :book_credit_reservations, dependent: :restrict_with_exception

  scope :available, -> { where(status: "available") }

  validates :status, inclusion: { in: %w[available reserved consumed] }

  def self.reserve_for!(book)
    user = book.user
    return if user.admin?

    user.with_lock do
      existing = BookCreditReservation.held.find_by(book: book)
      return existing if existing

      credit = user.book_credits.available.order(:id).first
      raise LimitReached unless credit

      reservation = credit.book_credit_reservations.create!(user: user, book: book)
      credit.update!(status: "reserved")
      reservation
    end
  end
end
