# frozen_string_literal: true

module ParentAuthorization
  extend ActiveSupport::Concern

  PARENT_SESSION_DURATION = 30.minutes

  included do
    helper_method :parental_purchase_pin_required?
  end

  private

  def parent_control
    @parent_control ||= current_user&.parent_control
  end

  def parent_authorized?
    data = session[:parent_access]
    return false unless parent_control&.enabled? && data && data["user_id"] == current_user.id
    return false unless ActiveSupport::SecurityUtils.secure_compare(data["pin_key"].to_s, parent_control.session_key)

    Time.zone.at(data["authenticated_at"].to_i) >= PARENT_SESSION_DURATION.ago
  end

  def authorize_parent_session!
    session[:parent_access] = {
      user_id: current_user.id,
      authenticated_at: Time.current.to_i,
      pin_key: parent_control.session_key
    }
  end

  def parental_purchase_pin_required?
    return false unless request.env["warden"]

    parent_control&.enabled? && !parent_authorized?
  end

  def authorize_parental_purchase!(fallback_location:)
    return true unless parental_purchase_pin_required?

    if params[:parent_pin].blank?
      redirect_to fallback_location, alert: I18n.t("parent.purchase.pin_required"), status: :see_other
      return false
    end

    if parent_control.authenticate_access_pin(params[:parent_pin].to_s)
      authorize_parent_session!
      true
    else
      key = parent_control.reload.pin_locked? ? "parent.session.locked" : "parent.session.incorrect"
      redirect_to fallback_location, alert: I18n.t(key), status: :see_other
      false
    end
  end
end
