# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    before_action :configure_sign_in_params, only: [ :create ]
    skip_before_action :check_tutorial, only: [ :destroy ]

    # GET /resource/sign_in
    def new
      Current.visitor.presence && Current.visitor.update!(user: current_user)
      super
    end

    # POST /resource/sign_in
    def create
      Current.visitor.presence && Current.visitor.update!(user: current_user)
      super
    end

    def destroy
      super
    end

    # DELETE /resource/sign_out

    protected

    # If you have extra params to permit, append them to the sanitizer.
    def configure_sign_in_params
      devise_parameter_sanitizer.permit(:sign_in, keys: [ :attribute ])
    end
  end
end



# figure out logout issue with tutorial controller
