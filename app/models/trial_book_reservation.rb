# frozen_string_literal: true

class TrialBookReservation < ApplicationRecord
  class LimitReached < StandardError; end
  class TrialExpired < StandardError; end

  belongs_to :user
  belongs_to :book, optional: true
  belongs_to :released_by, class_name: "User", optional: true

  scope :held, -> { where(status: "held") }

  validates :status, inclusion: { in: %w[held released] }

  def self.reserve_for!(book)
    user = book.user
    return unless user.trial?

    user.with_lock do
      existing = held.find_by(book: book)
      return existing if existing
      raise TrialExpired if user.trial_expired?
      raise LimitReached if user.trial_book_reservations.held.count >= User::TRIAL_BOOK_LIMIT

      create!(user: user, book: book)
    end
  end

  def release!(by: nil, reason:)
    with_lock do
      return false unless status == "held"

      update!(status: "released", released_at: Time.current, released_by: by, release_reason: reason)
    end
    true
  end
end
