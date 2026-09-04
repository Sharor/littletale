# frozen_string_literal: true

OmniAuth.config do |config|
  config.allowed_request_methods = %i[get post]
  config.omniauth_path_prefix = "/users/auth"
end
