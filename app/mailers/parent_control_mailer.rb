# frozen_string_literal: true

class ParentControlMailer < ApplicationMailer
  default from: ENV.fetch("RESEND_FROM_EMAIL", "LittleTale <onboarding@resend.dev>")

  def pin_reset
    @control = params.fetch(:control)
    @user = @control.user
    @reset_url = edit_parent_pin_reset_url(token: @control.generate_token_for(:pin_reset))

    mail(to: @user.email, subject: "Reset your LittleStories parent PIN")
  end
end
