# frozen_string_literal: true

class BookGift < ApplicationRecord
  class NotGiftable < StandardError; end
  class RecipientMismatch < StandardError; end
  class UnverifiedRecipient < StandardError; end

  belongs_to :source_book, class_name: "Book", optional: true
  belongs_to :sender, class_name: "User", optional: true
  belongs_to :recipient, class_name: "User", optional: true
  has_many :gift_pages, -> { order(:position) }, dependent: :destroy, inverse_of: :book_gift

  attr_reader :invitation_token

  before_validation :normalize_recipient_email

  validates :recipient_name, :recipient_email, :sender_callname, :message, :title, :token_digest,
    :issuance_key, :invitation_token_ciphertext, presence: true
  validates :issuance_key, uniqueness: true
  validates :language, inclusion: { in: User::SUPPORTED_LANGUAGES.keys }
  validates :delivery_status, inclusion: { in: %w[not_sent queued sent failed] }
  validate :recipient_email_is_gmail

  def self.issue!(source_book:, sender:, attributes:)
    raise NotGiftable unless source_book.user_id == sender.id && source_book.giftable?

    attributes = attributes.to_h.with_indifferent_access
    issuance_key = attributes[:issuance_key].presence || SecureRandom.uuid
    existing = sender.sent_book_gifts.find_by(issuance_key: issuance_key)
    return restore_existing_issue(existing) if existing

    raw_token = SecureRandom.urlsafe_base64(32)
    gift = nil

    transaction do
      gift = create!(
        attributes.merge(
          issuance_key: issuance_key,
          source_book: source_book,
          sender: sender,
          title: source_book.name,
          token_digest: digest_token(raw_token),
          invitation_token_ciphertext: encrypt_token(raw_token)
        )
      )
      source_book.current_pages.each_with_index do |page, index|
        retained_page = gift.gift_pages.create!(position: index + 1, text: page.text.to_s)
        retained_page.copy_image_from!(page.illustration.original_image) if page.illustration&.original_image&.present?
      end
    end

    gift.instance_variable_set(:@invitation_token, raw_token)
    gift.instance_variable_set(:@issued_now, true)
    gift
  rescue ActiveRecord::RecordNotUnique
    restore_existing_issue(sender.sent_book_gifts.find_by!(issuance_key: issuance_key))
  rescue StandardError
    gift&.destroy! if gift&.persisted?
    raise
  end

  def issued_now?
    @issued_now == true
  end

  def reload(...)
    @invitation_token = nil
    @issued_now = false
    super
  end

  def rotate_invitation_token!
    raw_token = SecureRandom.urlsafe_base64(32)
    update!(
      token_digest: self.class.send(:digest_token, raw_token),
      invitation_token_ciphertext: self.class.send(:encrypt_token, raw_token)
    )
    @invitation_token = raw_token
  end

  def recovered_invitation_token
    self.class.send(:decrypt_token, invitation_token_ciphertext)
  end

  def self.find_by_invitation_token(raw_token)
    return if raw_token.blank?

    find_by(token_digest: digest_token(raw_token))
  end

  def claim!(user)
    with_lock do
      raise RecipientMismatch unless user.email.to_s.casecmp?(recipient_email)
      raise UnverifiedRecipient unless user.google_email_verified?
      raise RecipientMismatch if recipient_id.present? && recipient_id != user.id

      update!(recipient: user, claimed_at: Time.current) unless claimed_at?
    end
    true
  end

  def self.restore_existing_issue(gift)
    gift.instance_variable_set(:@invitation_token, gift.recovered_invitation_token)
    gift.instance_variable_set(:@issued_now, false)
    gift
  end
  private_class_method :restore_existing_issue

  def self.token_encryptor
    key = Rails.application.key_generator.generate_key(
      "book-gift-invitation-token",
      ActiveSupport::MessageEncryptor.key_len
    )
    ActiveSupport::MessageEncryptor.new(key)
  end
  private_class_method :token_encryptor

  def self.encrypt_token(raw_token)
    token_encryptor.encrypt_and_sign(raw_token)
  end
  private_class_method :encrypt_token

  def self.decrypt_token(ciphertext)
    token_encryptor.decrypt_and_verify(ciphertext)
  end
  private_class_method :decrypt_token

  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest_token

  private

  def normalize_recipient_email
    self.recipient_email = recipient_email.to_s.strip.downcase.presence
  end

  def recipient_email_is_gmail
    return if recipient_email.blank? || recipient_email.match?(/\A[^@\s]+@gmail\.com\z/i)

    errors.add(:recipient_email, :gmail_only)
  end
end
