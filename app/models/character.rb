class Character < ApplicationRecord
    enum :generation_status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }
    # Relations
    belongs_to :user
    has_and_belongs_to_many :books
    has_one :illustration
    has_many :action_logs, as: :trackable
    belongs_to :current_image_request, class_name: "CharacterImageRequest", optional: true
    has_many :character_image_requests, dependent: :nullify
    has_one_attached :photo
    # Updates
    after_update_commit :broadcast_status_change, if: :saved_change_to_generation_status?

    # Virtual fields
    attr_accessor :creation_mode

    # Validations
    before_validation :normalize_roles
    validate :validate_roles
    with_options if: -> { creation_mode == "form" } do |form|
        form.validates :name, presence: true, uniqueness: { scope: :user }
        form.validates :age, presence: true
        form.validates :gender, presence: true
        form.validates :ethnicity, presence: true
        form.validates :hair_color, presence: true
        form.validates :hair_style, presence: true
        form.validates :eye_color, presence: true
    end
    validates :photo, presence: true, if: -> { creation_mode == "photo" }
    validates :name, presence: true, uniqueness: { scope: :user }

    # Constants
    ETHNICITIES = %w[White Black Asian Latino Indigenous]
    HAIRSTYLES = %w[Long Loose Short Bald Ponytail Braids]
    HAIRCOLORS = %w[Brown Blond White Red]
    EYECOLORS = %w[Brown Blue Green Grey]
    GENDERS = %w[Boy Girl Man Woman]
    ROLE_GROUPS = {
        "Family" => [ "Father", "Mother", "Big sibling", "Middle sibling", "Younger sibling" ].freeze,
        "Appearance" => %w[Tattoos Piercings Freckles].freeze,
        "Story" => %w[Hero Villain Supporting].freeze
    }.freeze
    ROLES = ROLE_GROUPS.values.flatten.freeze
    EXCLUSIVE_ROLE_GROUPS = %w[Family Story].freeze
    BOOK_GENERATION_FIELDS = %w[id name age gender ethnicity hair_color hair_style eye_color roles].freeze

    TRIAL_CHARACTER_LIMIT = 3
    TRIAL_USER_LIMIT = 24

    def book_generation_metadata
        attributes.slice(*BOOK_GENERATION_FIELDS)
    end

    def can_perform_action?(action_name)
        return true if user.admin?
        character_action_count = action_logs.for_action(action_name).count
        user_action_count = user.action_logs.for_action(action_name).count

        character_action_count < TRIAL_CHARACTER_LIMIT && user_action_count < TRIAL_USER_LIMIT
    end

    def record_action!(action_name)
        raise "Limit reached" unless can_perform_action?(action_name)

        action_logs.create!(action: action_name, user: user)
    end

    def generation_description
        base = "#{pronoun_conversion.capitalize} is a #{self.age} year old #{self.ethnicity.downcase} #{self.gender.downcase} with #{self.eye_color.downcase} eyes."
        hair = "#{pronoun_conversion.capitalize} has #{self.hair_color.downcase} hair color, and hair style is #{self.hair_style.downcase}."
        "#{base} #{hair}" # if self.role.blank? FIXTHIS
    end

    def pronoun_conversion
        return "he" if [ "Boy", "Man" ].include? self.gender
        "she" if [ "Girl", "Woman" ].include? self.gender
    end

    def setup_illustration(char_id_from_frontend = nil)
        CharacterImageRequest.submit!(self)
    end

    def broadcast_image_status
        broadcast_replace_to(user, :characters,
          target: "illustration_section_#{id}", partial: "illustrations/illustration",
          locals: { character: self })
    end

    def image_ready_for_book?
        return false unless completed? && illustration&.original_image&.present?
        return true unless current_image_request

        current_image_request.current? && current_image_request.screening_status == "approved" &&
          current_image_request.generation_attempt&.status == "completed" &&
          current_image_request.generation_attempt.illustration_id == illustration.id
    end

    private

    def normalize_roles
        self.roles = [] if roles.nil?
        return unless roles.is_a?(Array)

        self.roles = roles.map do |role|
            next role unless role.is_a?(String)

            value = role.strip
            ROLES.find { |allowed| allowed.casecmp?(value) } || value
        end.reject { |role| role == "" }.uniq
    end

    def validate_roles
        unless roles.is_a?(Array) && roles.all? { |role| role.is_a?(String) }
            errors.add(:roles, "must be a list of role names")
            return
        end

        errors.add(:roles, "contain an unknown role") if (roles - ROLES).any?
        EXCLUSIVE_ROLE_GROUPS.each do |group|
            if (roles & ROLE_GROUPS.fetch(group)).size > 1
                errors.add(:roles, "Choose only one #{group.downcase} role.")
            end
        end
    end

    def broadcast_status_change
        broadcast_image_status
    end
end
