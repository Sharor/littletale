# frozen_string_literal: true

require "digest"

class ParentalGenerationGate
  class LimitReached < StandardError; end

  Decision = Data.define(:status, :request) do
    def allowed? = status == :allowed
    def pending? = status == :pending
    def limit_reached? = status == :limit_reached
  end

  def self.authorize(generatable, retrying: false)
    new(generatable, retrying: retrying).authorize
  end

  def self.request_key_for(generatable)
    new(generatable, retrying: false).send(:request_key)
  end

  def initialize(generatable, retrying:)
    @generatable = generatable
    @user = generatable.user
    @retrying = retrying
  end

  def authorize
    if user.admin?
      user.parental_generation_requests.where(generatable: generatable, status: %w[pending approved])
        .update_all(status: "released", updated_at: Time.current)
      return Decision.new(status: :allowed, request: nil)
    end

    control = user.parent_control
    return Decision.new(status: :allowed, request: nil) unless control&.enabled?

    if control.effective_mode == "daily_limit"
      if kind == "character"
        control.generation_requests.pending.where(generatable: generatable)
          .update_all(status: "released", updated_at: Time.current)
        return Decision.new(status: :allowed, request: nil)
      end

      authorize_daily_book(control)
    else
      authorize_with_approval(control)
    end
  end

  private

  attr_reader :generatable, :user, :retrying

  def authorize_with_approval(control)
    control.generation_requests.where(generatable: generatable, status: %w[pending approved]).where.not(request_key: request_key)
      .update_all(status: "released", updated_at: Time.current)
    existing = active_request(control)
    if existing&.status == "approved"
      return Decision.new(status: :allowed, request: existing)
    end
    return Decision.new(status: :pending, request: existing) if existing
    return Decision.new(status: :allowed, request: nil) if retrying

    request = control.generation_requests.create!(request_attributes(status: "pending"))
    Decision.new(status: :pending, request: request)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def authorize_daily_book(control)
    control.with_lock do
      existing = active_request(control)
      if existing&.approved? &&
          (existing.policy_mode == "daily_limit" || generatable.pending? || generatable.in_progress?)
        return Decision.new(status: :allowed, request: existing)
      end

      active_book_ids = user.books.active.where(generation_status: %i[pending in_progress]).select(:id)
      in_progress = control.generation_requests.where(kind: "book", status: "approved",
        generatable_type: "Book", generatable_id: active_book_ids).count
      completed_today = control.generation_requests.where(kind: "book", status: "completed",
        completed_at: control.local_day_range).count
      if in_progress + completed_today >= control.daily_book_limit
        return Decision.new(status: :limit_reached, request: nil)
      end

      attributes = { status: "approved", policy_mode: "daily_limit", reserved_on: control.local_date,
        decided_at: Time.current }
      request = if existing
        existing.tap { |record| record.update!(attributes) }
      else
        control.generation_requests.create!(request_attributes(status: "approved").merge(attributes.except(:status)))
      end
      Decision.new(status: :allowed, request: request)
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def active_request(control)
    control.generation_requests.where(generatable: generatable, request_key: request_key,
      status: %w[pending approved]).order(:id).last
  end

  def request_attributes(status:)
    {
      user: user,
      generatable: generatable,
      kind: kind,
      policy_mode: user.parent_control.effective_mode,
      request_key: request_key,
      status: status
    }
  end

  def kind
    generatable.is_a?(Book) ? "book" : "character"
  end

  def request_key
    @request_key ||= if generatable.is_a?(Book)
      Digest::SHA256.hexdigest([
        generatable.attributes.slice("name", "plot", "total_pages", "language", "reader_age", "art_style"),
        generatable.character_ids.sort
      ].to_json)
    else
      CharacterImageRequest.snapshot_for(generatable).fetch(:fingerprint)
    end
  end
end
