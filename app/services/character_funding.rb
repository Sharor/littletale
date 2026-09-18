# frozen_string_literal: true

class CharacterFunding
  def self.funded?(request)
    request.reload
    return true if %w[trial admin].include?(request.funding_source)

    CharacterCreditReservation.where(character_image_request: request, status: %w[held consumed]).exists?
  end

  def self.reserve_for!(request)
    request.reload
    return if %w[trial admin].include?(request.funding_source)

    existing = request.character_credit_reservations.order(:id).last
    return existing if existing && %w[held consumed].include?(existing.status)

    user = request.user.reload
    if user.admin?
      request.update!(funding_source: "admin")
      return
    end
    if user.trial?
      request.update!(funding_source: "trial")
      return
    end

    reservation = CharacterCredit.reserve_for!(request)
    request.update!(funding_source: "credit")
    reservation
  end

  def self.release!(request, by: nil, reason:)
    reservation = request.character_credit_reservations.held.order(:id).last
    reservation&.release!(by: by, reason: reason) || false
  end

  def self.consume!(request)
    reservation = request.character_credit_reservations.held.order(:id).last
    reservation&.consume! || false
  end

  def self.release_for_admin!(request, admin:)
    raise ArgumentError, "Administrator required" unless admin&.admin?

    request.user.with_lock do
      request.with_lock do
        request.association(:generation_attempt).reset
        request.assessment.reload
        return :active unless admin_releasable?(request)

        reservation = request.character_credit_reservations.held.order(:id).last
        return :missing unless reservation

        return reservation.release!(by: admin, reason: "admin_released_failed_character") ? :released : :missing
      end
    end
  end

  def self.admin_releasable?(request)
    attempt_status = request.generation_attempt&.status
    return %w[failed outcome_unknown].include?(attempt_status) if attempt_status

    %w[unavailable needs_review rejected].include?(request.assessment.status)
  end
end
