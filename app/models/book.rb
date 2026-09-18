class Book < ApplicationRecord
  enum :generation_status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }
  belongs_to :user

  has_many :trial_book_reservations, dependent: :nullify

  has_many :book_wardrobe_plans, dependent: :destroy

  def current_wardrobe_plan
    book_wardrobe_plans.find_by(generation_attempt: generation_attempt)
  end

  has_one :chatgpt
  has_and_belongs_to_many :characters
  has_many :pages
  has_many :illustrations, through: :pages

  validates :name, presence: true

  broadcasts_to ->(book) { book }, inserts_by: :replace

  after_update_commit :start_owner_trial, if: -> { saved_change_to_generation_status? && completed? }

  # after_update_commit -> {
  #   broadcast_replace_later_to self,
  #     target: ActionView::RecordIdentifier.dom_id(self, :state),
  #     partial: "books/book_state",
  #     locals: { book: self }
  # }

  validates :total_pages, presence: true, numericality: { greater_than: 0 }
  validate :total_pages_within_tier_limit

  TIER_LIMITS = {
    "free"       => 5,
    "basic"      => 10,
    "adventurer" => 15,
    "premium"    => 20
  }.freeze

  def tier_limit
    TIER_LIMITS.fetch(user.tier, 5)
  end

  def total_pages_within_tier_limit
    return unless total_pages.present?

    if total_pages > tier_limit
      errors.add(:total_pages, "cannot exceed #{tier_limit} pages for the #{user.tier.capitalize} tier")
    end
  end

  # For frontend purposes
  def construction_level
    return 0 if total_pages.to_i.zero?

    percent = (current_pages.count.to_f / total_pages * 100).round
    case percent
    when 0..19   then 1 # Foundation
    when 20..39  then 2 # Walls
    when 40..59  then 3 # Towers
    when 60..79  then 4 # Roofs
    when 80..94  then 5 # Flag Raised
    else              6 # Magical Glow (100%)
    end
  end

  # Generation logic

  def characters_ready_for_generation?
    characters.all? { |character| character.user_id == user_id && character.image_ready_for_book? }
  end

  def ensure_character_images_ready!
    return true if characters_ready_for_generation?

    failure = generation_failure_context(
      "type" => "character_image_not_ready",
      "message" => "One or more selected character images are not ready. Choose ready characters before starting this book."
    )
    update_columns(generation_status: self.class.generation_statuses.fetch("failed"),
      generation_failed_at: Time.current,
      generation_failure: failure)
    broadcast_generation_state
    false
  end

  def write_storyline
    Rails.logger.error("Chatpgt id:#{chatgpt.id} had no answer for book.rb.") && return if chatgpt.answer.blank?

    JSON.parse(chatgpt.answer)
  end

  def current_pages
    pages.where(generation_attempt: generation_attempt).order(:story_position, :id)
  end

  def create_pages_from_answer(json, attempt: generation_attempt)
    if json["wardrobe_plan_id"]
      plan = book_wardrobe_plans.find(json["wardrobe_plan_id"])
      return unless reload.generation_attempt == attempt && plan.generation_attempt == attempt && plan.ready?
      page = plan.pages.find_by!(story_position: json.fetch("position"))
      return unless page.wardrobe_ready?
      page.illustration.generate_image_v1(characters)
      return page
    end
    page = pages.create!(text: json["story"], generation_attempt: attempt)
    page.illustration = Illustration.create!(original_description: json["image"])
    # You need to finish this by doing a comparison of page["present"] and characters in Book. TODO maybe?
    page.illustration.generate_image_v1(characters)
    page
  end

  def record_generation_failure!(illustration:, failure:, request:)
    with_lock do
      return unless illustration.page.generation_attempt == generation_attempt

      context = generation_failure_context(failure.merge(
        "book_id" => id,
        "page_id" => illustration.page_id,
        "illustration_id" => illustration.id,
        "generation_attempt" => generation_attempt,
        "request" => request,
        "book_context" => generation_context
      ))

      update!(
        generation_status: :failed,
        generation_failed_at: Time.current,
        generation_failure: context,
        generation_failure_history: generation_failure_history + [ context ]
      )
    end
    broadcast_generation_state
  end

  def refresh_generation_status!(attempt: generation_attempt)
    with_lock do
      return unless attempt == generation_attempt
      return unless current_pages.count >= total_pages
      return unless current_pages.all? { |page| page.illustration&.original_image&.present? }

      reserve_trial_slot!
      update!(generation_status: :completed, generation_failure: {}, generation_failed_at: nil)
    end
    broadcast_generation_state
  end

  def prepare_for_regeneration!
    with_lock do
      advance_generation_attempt!
    end
  end

  def prepare_failed_regeneration!
    with_lock do
      return unless failed?

      reserve_trial_slot!
      advance_generation_attempt!
    end
  end

  def reserve_trial_slot!
    TrialBookReservation.reserve_for!(self)
  end

  def enqueue_generation!(attempt: nil)
    reservation = reserve_trial_slot!
    job = attempt ? GenerateBookJob.perform_later(id, attempt) : GenerateBookJob.perform_later(id)
    return true if job&.successfully_enqueued?

    fail_generation_enqueue!(reservation)
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    fail_generation_enqueue!(reservation)
  end

  def enqueue_illustration_retry!(illustration, actor:)
    reservation_details = with_lock do
      return false unless PageIllustrationGeneration.available?(illustration, admin: actor)

      attempts_before = PageIllustrationGeneration.attempts(illustration).length
      book_attempts_before = current_illustration_attempt_count
      reservation = reserve_trial_slot!
      newly_reserved = reservation&.previously_new_record?
      token = PageIllustrationGeneration.reserve!(illustration, retrying: true, admin: actor)
      unless token
        attempts_after = PageIllustrationGeneration.attempts(illustration.reload).length
        if newly_reserved && attempts_after == attempts_before
          reservation.release!(reason: "illustration_retry_enqueue_failed")
        end
        return false
      end

      [ token, reservation, newly_reserved, attempts_before, book_attempts_before, generation_attempt ]
    end

    token, reservation, newly_reserved, attempts_before, book_attempts_before,
      reserved_generation_attempt = reservation_details
    queued = PageIllustrationGeneration.enqueue_reserved!(illustration, token)
    release_unused_illustration_retry_slot!(reservation, illustration,
      attempts_before: attempts_before, book_attempts_before: book_attempts_before,
      generation_attempt: reserved_generation_attempt) if !queued && newly_reserved
    queued
  end

  def illustration_retry_in_progress?
    current_pages.includes(:illustration).any? do |page|
      page.illustration && %w[queued running].include?(PageIllustrationGeneration.state(page.illustration)["status"])
    end
  end

  def release_trial_slot!(by:)
    with_lock do
      return :not_failed unless failed?
      return :retrying if illustration_retry_in_progress?

      reservation = trial_book_reservations.held.order(:id).last
      return :missing unless reservation&.release!(by: by, reason: "admin_released_failed_book")

      :released
    end
  end

  def generation_failure_context(failure)
    failure.deep_stringify_keys.merge("account_access" => user.access_type)
  end

  def fail_generation_enqueue!(reservation)
    reservation&.release!(reason: "queue_enqueue_failed")
    message = if reservation
      "Book generation could not be queued. The trial book slot was released."
    else
      "Book generation could not be queued."
    end
    update!(generation_status: :failed, generation_failed_at: Time.current,
      generation_failure: generation_failure_context(
        "type" => "book_enqueue_failed",
        "message" => message
      ))
    false
  end

  def finished_generation?
    current_pages.any? { |page| page&.illustration&.original_image&.present? }
  end

  def progress?
    current_pages.select { |page| page&.illustration&.original_image&.present? }.count
  end

  private

  def generation_context
    {
      "name" => name,
      "plot" => plot,
      "total_pages" => total_pages,
      "characters" => characters.map do |character|
        illustration = character.illustration
        {
          "id" => character.id,
          "name" => character.name,
          "age" => character.age,
          "gender" => character.gender,
          "illustration_id" => illustration&.id,
          "reference_image" => illustration&.original_image&.identifier
        }
      end,
      "chatgpt_id" => chatgpt&.id,
      "story_response" => chatgpt&.answer
    }
  end

  def advance_generation_attempt!
    history = generation_failure_history
    history += [ generation_failure ] if generation_failure.present? && !history.include?(generation_failure)

    update!(
      generation_attempt: generation_attempt + 1,
      generation_status: :pending,
      generation_failure: {},
      generation_failed_at: nil,
      generation_failure_history: history
    )
    generation_attempt
  end

  def release_unused_illustration_retry_slot!(reservation, illustration, attempts_before:, book_attempts_before:,
    generation_attempt:)
    with_lock do
      return unless failed? && self.generation_attempt == generation_attempt
      return if illustration_retry_in_progress?
      return unless PageIllustrationGeneration.attempts(illustration.reload).length == attempts_before
      return unless current_illustration_attempt_count == book_attempts_before

      reservation.reload.release!(reason: "illustration_retry_enqueue_failed") if reservation.status == "held"
    end
  end

  def current_illustration_attempt_count
    current_pages.includes(:illustration).sum do |page|
      page.illustration ? PageIllustrationGeneration.attempts(page.illustration).length : 0
    end
  end

  def broadcast_generation_state
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :state),
      partial: "books/book_state",
      locals: { book: self }
    )
  end

  def start_owner_trial
    user.start_trial! if trial_book_reservations.held.exists?
  end
end
