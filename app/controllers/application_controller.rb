class ApplicationController < ActionController::Base
  include SetCurrentVisitor
  include TrackEvent

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  helper_method :browser

  before_action :enforce_trial_access
  before_action :check_tutorial, except: %i[ track_user ]
  skip_before_action :check_tutorial, if: -> { devise_controller? && action_name == "destroy"  }



  def browser
    @browser ||= Browser.new(request.user_agent, accept_language: request.accept_language)
  end


  def check_tutorial
    return unless user_signed_in?


    redirect_to terms_url unless current_user.tutorial&.terms
    # @url = eula_url unless current_user.tutorial&.eula # Do we want a EULA?
    # redirect_to @url unless.. (didnt check this works so)
  end

  def new_session_path(_scope)
    new_user_session_path
  end

  def track_user
    return unless user_signed_in? && new_session

    Current.visitor.presence && Current.visitor.update!(user: current_user)
    session[:last_activity] = Time.zone.now
  end

  def new_session
    session[:last_activity].blank? || session[:last_activity] < (1.hour.ago)
  end

  private

  def enforce_trial_access
    return unless user_signed_in? && current_user.trial_expired?
    return if devise_controller? || %w[settings purchases subscriptions].include?(controller_path)

    if request.format.html? || request.format.turbo_stream?
      redirect_to settings_url, alert: "Your trial has ended. Subscribe to continue.",
        status: request.get? ? :found : :see_other
    else
      render json: { error: "trial_expired", settings_url: settings_url }, status: :payment_required
    end
  end
end
