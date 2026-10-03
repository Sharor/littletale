class Admin::TestEmailsController < ApplicationController
  skip_before_action :check_tutorial
  before_action -> { head :forbidden unless current_user&.admin? }

  def create
    AdminHealthMailer.with(
      admin: current_user,
      locale: I18n.locale,
      idempotency_key: SecureRandom.uuid
    ).test_email.deliver_now

    redirect_to admin_root_path, notice: I18n.t("admin.health.email.submitted", email: current_user.email)
  rescue StandardError => error
    Rails.logger.warn("Admin test email submission failed (#{error.class})")
    redirect_to admin_root_path, alert: I18n.t("admin.health.email.failed")
  end
end
