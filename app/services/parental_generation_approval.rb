# frozen_string_literal: true

class ParentalGenerationApproval
  def self.call(generation_request, allow_declined: false)
    new(generation_request, allow_declined: allow_declined).call
  end

  def initialize(generation_request, allow_declined:)
    @generation_request = generation_request
    @allow_declined = allow_declined
  end

  def call
    generatable.with_lock do
      generation_request.reload
      return :stale unless approvable?
      unless generation_request.request_key == ParentalGenerationGate.request_key_for(generatable)
        generation_request.release!
        return :stale
      end

      generatable.restore! if generatable.is_a?(Book) && generatable.deleted_at?
      generation_request.approve!
    end

    if generation_request.kind == "book"
      reservation = generatable.reserve_generation_funding!
      queued = generatable.enqueue_generation!(reservation: reservation,
        release_on_failure: reservation&.previously_new_record? || false)
      return :enqueue_failed unless queued
    else
      generatable.setup_illustration
    end
    :approved
  end

  private

  attr_reader :generation_request, :allow_declined

  def generatable
    @generatable ||= generation_request.generatable
  end

  def approvable?
    generation_request.pending? || (allow_declined && generation_request.status == "declined")
  end
end
