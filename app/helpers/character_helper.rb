# app/helpers/character_helper.rb
module CharacterHelper
  # Replicates the JS logic for displaying options (e.g., 'hair_style' becomes 'Hair Style')
  def format_option_for_display(option)
    key = option.to_s.parameterize(separator: "_")
    I18n.t("characters.options.#{key}", default: option.to_s.split("_").map(&:capitalize).join(" "))
  end

  # Provides all character option arrays, assuming constants are defined in the Character model
  def character_options
    # NOTE: You must ensure Character model defines these constants (e.g., Character::GENDERS)
    {
      gender: Character::GENDERS,          # FIX: Changed key to :gender
      ethnicity: Character::ETHNICITIES,    # FIX: Changed key to :ethnicity
      hair_style: Character::HAIRSTYLES,    # FIX: Changed key to :hair_style
      hair_color: Character::HAIRCOLORS,    # FIX: Changed key to :hair_color
      eye_color: Character::EYECOLORS,      # FIX: Changed key to :eye_color
      roles: Character::ROLES
    }
  rescue NameError
    # Provide dummy data if your constants are not yet defined to prevent crashes
    {
      gender: [ "male", "female" ],
      ethnicity: [ "asian", "caucasian" ],
      hair_style: [ "long", "short" ],
      hair_color: [ "black", "brown" ],
      eye_color: [ "blue", "brown" ],
      roles: [ "protagonist", "antagonist" ]
    }
  end
end
