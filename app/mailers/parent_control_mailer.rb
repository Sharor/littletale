# frozen_string_literal: true

class ParentControlMailer < ApplicationMailer
  def pin_reset
    @control = params.fetch(:control)
    @user = @control.user
    @reset_url = edit_parent_pin_reset_url(token: @control.generate_token_for(:pin_reset))

    mail(to: @user.email, subject: "Reset your MinorTale parent PIN")
  end
end
