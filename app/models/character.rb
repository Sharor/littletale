class Character < ApplicationRecord
    enum :generation_status, { pending: 0, in_progress: 1, completed: 2 }
    # Relations
    belongs_to :user
    has_and_belongs_to_many :books
    has_one :illustration
    has_many :action_logs, as: :trackable, dependent: :destroy
    has_one_attached :photo
    # Updates
    after_update_commit :broadcast_status_change, if: :saved_change_to_generation_status?

    # Virtual fields
    attr_accessor :creation_mode

    # Validations
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
    ROLES = %w[Father Mother Tattoos Piercings Freckles Hero Villain]

    TRIAL_CHARACTER_LIMIT = 3
    TRIAL_USER_LIMIT = 24

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
        if can_perform_action?("setup_illustration")
            if self.photo.attached?
                CartoonImageJob.perform_later(self.id, char_id_from_frontend)
            else
                GenerateImageJob.perform_later(self.id, generation_description())
            end
            record_action!("setup_illustration")
        else
            Rails.logger.info "Do better error when hitting trial limit."
        end
    end

    private

    def broadcast_status_change
        broadcast_replace_to(
        "characters", # This must match the stream name in your index view
        target: ActionView::RecordIdentifier.dom_id(self, :illustration),
        partial: "illustrations/illustration",
        locals: { character: self }
        )
    end
end
