# frozen_string_literal: true

class BookFunding
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
end
