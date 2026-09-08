json.extract! character, :id, :name, :age, :hair_color, :hair_style, :eye_color, :ethnicity, :roles, :created_at, :updated_at
json.url character_url(character, format: :json)

json.screening_status character.current_image_request&.screening_status
json.rejection_reason character.current_image_request&.public_reason
json.generation_status character.generation_status
