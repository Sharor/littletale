class AdminHealthMailer < ApplicationMailer
  default from: ENV.fetch("RESEND_FROM_EMAIL", "LittleTale <onboarding@resend.dev>")

  def test_email
    @admin = params.fetch(:admin)

    I18n.with_locale(params.fetch(:locale, I18n.default_locale)) do
      mail(
        to: @admin.email,
        subject: I18n.t("admin.health.email.subject"),
        options: { idempotency_key: params[:idempotency_key] }
      )
    end
  end
end
