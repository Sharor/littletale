# frozen_string_literal: true

json.extract! illustration, :id, :image, :created_at, :updated_at
json.url illustration_url(illustration, format: :json)
