# frozen_string_literal: true

class BookFunding
  class IncompleteBook < StandardError; end

  def self.reserve_for!(book)
    user = book.user
    user.reload
    return if user.admin?

    trial_reservation = book.trial_book_reservations.held.order(:id).last
    return trial_reservation if trial_reservation

    credit_reservation = book.book_credit_reservations.where(status: %w[held consumed]).order(:id).last
    return credit_reservation if credit_reservation

    user.trial? ? TrialBookReservation.reserve_for!(book) : BookCredit.reserve_for!(book)
  end

  def self.held_for(book)
    book.trial_book_reservations.held.order(:id).last ||
      book.book_credit_reservations.held.order(:id).last
  end

  def self.convert_trial_to_paid_for_gift!(book)
    raise IncompleteBook unless book.completed?

    user = book.user
    user.with_lock do
      book.reload
      existing = paid_reservation_for(book)
      return existing if existing

      trial_reservation = book.trial_book_reservations.held.order(:id).last

      credit = user.book_credits.spendable.includes(:book_purchase, :subscription_period).detect do |candidate|
        candidate.book_purchase&.paid? || candidate.subscription_period.present?
      end
      raise BookCredit::LimitReached unless credit

      now = Time.current
      reservation = credit.book_credit_reservations.create!(
        user: user,
        book: book,
        status: "consumed",
        consumed_at: now
      )
      credit.update!(status: "consumed")
      trial_reservation&.update!(
        status: "released",
        released_at: now,
        release_reason: "converted_to_paid_for_gift"
      )
      reservation
    end
  end

  def self.paid_reservation_for(book)
    book.book_credit_reservations.where(status: "consumed")
      .includes(book_credit: [ :book_purchase, :subscription_period ])
      .detect do |reservation|
        credit = reservation.book_credit
        credit.book_purchase&.paid? || credit.subscription_period.present?
      end
  end
  private_class_method :paid_reservation_for
end
