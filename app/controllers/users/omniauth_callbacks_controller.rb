# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_forgery_protection

    def google_oauth2
      authenticate_with_omniauth("Google", "devise.google_data")
    end

    def microsoft_v2_auth
      authenticate_with_omniauth("Microsoft", "devise.microsoft_data")
    end

    private

    def authenticate_with_omniauth(provider_name, session_key)
      @user = User.from_omniauth(request.env["omniauth.auth"])

      if @user.persisted?
        flash[:notice] = I18n.t "devise.omniauth_callbacks.success", kind: provider_name
        Current.visitor.presence && Current.visitor.update!(user: @user)
        sign_in_and_redirect @user, event: :authentication
      else
        session[session_key] = request.env["omniauth.auth"].except("extra")
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
      end
    end
  end
end
