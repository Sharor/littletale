require "digest"

class CharacterImageRequest < ApplicationRecord
  belongs_to :user
  belongs_to :character, optional: true
  belongs_to :assessment, class_name: "CharacterImageAssessment"
  has_one :generation_attempt, class_name: "CharacterImageGenerationAttempt", foreign_key: :request_id
  attr_readonly :user_id, :assessment_id, :original_character_id

  def self.submit!(character)
    request = nil
    character.user.with_lock do
      character.with_lock do
        photo = character.photo
        snapshot = snapshot_for(character)
        fingerprint = snapshot.fetch(:fingerprint)
        assessment = CharacterImageAssessment.find_or_create_by!(user: character.user, fingerprint: fingerprint) do |record|
          record.prompt = snapshot.fetch(:prompt)
          record.generation_model = snapshot.fetch(:generation_model)
          record.policy_version = CharacterImageAssessment::POLICY_VERSION
          record.photo.attach(photo.blob) if photo.attached?
        end
        request = find_or_create_by!(original_character_id: character.id, assessment: assessment) do |record|
          record.character = character
          record.user = character.user
        end
        if character.current_image_request_id != request.id
          character.update!(current_image_request: request, generation_status: :pending)
          previous = request.generation_attempt
          if previous&.status == "completed" && previous.illustration&.original_image&.present?
            Illustration.where(character_id: character.id).where.not(id: previous.illustration_id).update_all(character_id: nil)
            previous.illustration.update!(character_id: character.id)
            character.association(:illustration).reset
            character.completed!
          end
        end
      end
    end
    if request.assessment.status == "checking"
      ScreenCharacterImageJob.perform_later(request.assessment_id)
    elsif request.screening_status == "approved"
      request.enqueue_generation!
    end
    character.broadcast_image_status
    request
  end

  def self.snapshot_for(character)
    photo = character.photo
    illustration = Illustration.new
    prompt = if photo.attached?
      illustration.single_specification
    else
      "#{illustration.build_prompt} Character description: #{character.generation_description}\nMake only the character, nothing else. Make the background entirely light brown."
    end
    model = photo.attached? ? "gpt-image-1" : "dall-e-3"
    checksum = photo.attached? ? Digest::SHA256.hexdigest(photo.download) : nil
    fingerprint = Digest::SHA256.hexdigest([ checksum, prompt, model, "1024x1024", CharacterImageAssessment::POLICY_VERSION ].to_json)
    { prompt: prompt, generation_model: model, fingerprint: fingerprint }
  end

  def current?
    character.present? && character.reload.current_image_request_id == id &&
      self.class.snapshot_for(character).fetch(:fingerprint) == assessment.fingerprint
  rescue ActiveRecord::RecordNotFound
    false
  end

  def screening_status
    provider_rejected? ? "rejected" : assessment.status
  end

  def public_reason
    provider_rejected? ? rejection_reason : assessment.public_reason
  end

  def enqueue_generation!
    attempt = nil
    user.with_lock do
      with_lock do
        if current? && screening_status == "approved"
          attempt = generation_attempt
          if attempt.nil? && character.can_perform_action?("setup_illustration")
            log = character.record_action!("setup_illustration")
            attempt = create_generation_attempt!(action_log: log)
          end
        end
      end
    end
    if attempt && (attempt.status == "reserved" || (attempt.status == "failed" && attempt.result_image.attached?))
      GenerateCharacterImageJob.perform_later(attempt.id)
    end
    attempt
  end

  def reject_by_provider!(public_reason:, metadata: {})
    with_lock do
      unless provider_rejected?
        update!(provider_rejected: true, rejection_reason: public_reason)
        assessment.decisions.create!(user: user, request: self, outcome: "rejected",
          source: "provider", internal_reason: metadata.to_json, public_reason: public_reason)
      end
    end
    character&.broadcast_image_status if current?
  end
end
