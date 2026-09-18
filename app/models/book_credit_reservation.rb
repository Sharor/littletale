# frozen_string_literal: true

class BookCreditReservation < ApplicationRecord
  belongs_to :user
  belongs_to :book_credit
  belongs_to :book, optional: true
  belongs_to :released_by, class_name: "User", optional: true

  scope :held, -> { where(status: "held") }

  validates :status, inclusion: { in: %w[held released consumed] }

  def release!(by: nil, reason:)
    user.with_lock do
      with_lock do
        return false unless status == "held"

        update!(status: "released", released_at: Time.current, released_by: by, release_reason: reason)
        book_credit.update!(status: "available")
      end
    end
    true
  end

  def consume!
    user.with_lock do
      with_lock do
        return false unless status == "held"

        update!(status: "consumed", consumed_at: Time.current)
        book_credit.update!(status: "consumed")
      end
    end
    true
  end
end
