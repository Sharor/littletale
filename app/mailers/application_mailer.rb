class ApplicationMailer < ActionMailer::Base
  default from: Rails.application.config.x.brand.mailer_sender
  layout "mailer"
end
