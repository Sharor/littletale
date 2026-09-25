class Book < ApplicationRecord
  attr_reader :prepared_funding_reservation, :prepared_funding_newly_acquired

  before_validation :apply_generation_preferences, on: :create
  before_validation :normalize_categories

  enum :generation_status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }
  belongs_to :user

  has_many :trial_book_reservations, dependent: :nullify
  has_many :book_credit_reservations, dependent: :nullify
  has_many :book_gifts, foreign_key: :source_book_id, dependent: :nullify, inverse_of: :source_book

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

  after_update_commit :finalize_owner_funding, if: -> { saved_change_to_generation_status? && completed? }
  after_update_commit :enqueue_categorization!, if: -> { saved_change_to_generation_status? && completed? }

  # after_update_commit -> {
  #   broadcast_replace_later_to self,
  #     target: ActionView::RecordIdentifier.dom_id(self, :state),
  #     partial: "books/book_state",
  #     locals: { book: self }
  # }

  validates :total_pages, presence: true, numericality: { greater_than: 0 }
  validates :language, inclusion: { in: User::SUPPORTED_LANGUAGES.keys }
  validates :reader_age, numericality: { only_integer: true, in: 0..120 }, allow_nil: true
  validates :art_style, inclusion: { in: BookArtStyle.keys }
  validate :total_pages_within_tier_limit
  validate :art_style_is_immutable, on: :update
  validate :categories_are_known

  TIER_LIMITS = {
    "free"       => 5,
    "basic"      => 10,
    "adventurer" => 15,
    "premium"    => 20
  }.freeze

  def tier_limit
    TIER_LIMITS.fetch(user.tier, 5)
  end

  def art_style_definition
    BookArtStyle.fetch(art_style)
  end

  def art_style_prompt
    art_style_definition.prompt
  end

  def giftable?
    return false unless completed?

    book_credit_reservations.where(status: "consumed").includes(book_credit: [ :book_purchase, :subscription_period ])
      .any? do |reservation|
        credit = reservation.book_credit
        credit.book_purchase&.paid? || credit.subscription_period.present?
      end
  end

  def gift_preparable?
    completed?
  end

  def total_pages_within_tier_limit
    return unless total_pages.present?

    if total_pages > tier_limit
      errors.add(:total_pages, I18n.t("activerecord.errors.models.book.attributes.total_pages.tier_limit",
        limit: tier_limit, tier: user.tier.capitalize))
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

      reserve_generation_funding!
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

      @prepared_funding_reservation = reserve_generation_funding!
      @prepared_funding_newly_acquired = @prepared_funding_reservation&.previously_new_record? || false
      advance_generation_attempt!
    end
  end

  def reserve_generation_funding!
    BookFunding.reserve_for!(self)
  end

  alias_method :reserve_trial_slot!, :reserve_generation_funding!

  def enqueue_generation!(attempt: nil, reservation: nil, release_on_failure: nil)
    unless reservation
      reservation = reserve_generation_funding!
      release_on_failure = reservation&.previously_new_record? if release_on_failure.nil?
    end
    job = attempt ? GenerateBookJob.perform_later(id, attempt) : GenerateBookJob.perform_later(id)
    return true if job&.successfully_enqueued?

    fail_generation_enqueue!(reservation, release_reservation: release_on_failure)
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    fail_generation_enqueue!(reservation, release_reservation: release_on_failure)
  end

  def enqueue_categorization!
    job = CategorizeBookJob.perform_later(id, generation_attempt)
    unless job&.successfully_enqueued?
      Rails.logger.error("Could not enqueue categorization for Book #{id}")
      return false
    end

    update_column(:categorization_enqueued_at, Time.current)
    true
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    Rails.logger.error("Could not enqueue categorization for Book #{id}: #{error.message}")
    false
  end

  def enqueue_illustration_retry!(illustration, actor:)
    reservation_details = with_lock do
      return false unless PageIllustrationGeneration.available?(illustration, admin: actor)

      attempts_before = PageIllustrationGeneration.attempts(illustration).length
      book_attempts_before = current_illustration_attempt_count
      reservation = reserve_generation_funding!
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

      reservation = BookFunding.held_for(self)
      return :missing unless reservation&.release!(by: by, reason: "admin_released_failed_book")

      :released
    end
  end

  def generation_failure_context(failure)
    context = failure.deep_stringify_keys.merge("account_access" => user.access_type)
    if (reservation = book_credit_reservations.where(status: %w[held consumed]).order(:id).last)
      context.merge!(
        "funding_source" => "book_credit",
        "funding_reservation_id" => reservation.id,
        "purchase_id" => reservation.book_credit.book_purchase_id
      )
    elsif (reservation = trial_book_reservations.held.order(:id).last)
      context.merge!("funding_source" => "trial", "funding_reservation_id" => reservation.id)
    end
    context
  end

  def fail_generation_enqueue!(reservation, release_reservation:)
    released_funding = case reservation
    when BookCreditReservation then "book credit"
    when TrialBookReservation then "trial book slot"
    end
    released = release_reservation && reservation&.release!(reason: "queue_enqueue_failed")
    message = if released && released_funding
      "Book generation could not be queued. The #{released_funding} was released."
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

  def normalize_categories
    self.categories = Array(categories).filter_map { |category| category.to_s.strip.presence }.uniq
  end

  def categories_are_known
    errors.add(:categories, "contains an unknown category") if categories.any? { |category| !BookCategory.include?(category) }
  end

  def art_style_is_immutable
    errors.add(:art_style, "cannot be changed after the book is created") if will_save_change_to_art_style?
  end

  def apply_generation_preferences
    self.language ||= user&.language || "en"
    self.reader_age = user&.reader_age if reader_age.nil?
  end

  def generation_context
    {
      "name" => name,
      "plot" => plot,
      "total_pages" => total_pages,
      "language" => language,
      "reader_age" => reader_age,
      "art_style" => art_style_prompt,
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
      categories: [],
      categorization_enqueued_at: nil,
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
    I18n.with_locale(user.language.presence_in(User::SUPPORTED_LANGUAGES.keys) || I18n.default_locale) do
      broadcast_replace_to(
        self,
        target: ActionView::RecordIdentifier.dom_id(self, :state),
        partial: "books/book_state",
        locals: { book: self }
      )
    end
  end

  def finalize_owner_funding
    if trial_book_reservations.held.exists?
      user.start_trial!
    else
      book_credit_reservations.held.order(:id).last&.consume!
    end
  end
end
