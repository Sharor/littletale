# frozen_string_literal: true

class RefreshPrintOrderStatusJob < ApplicationJob
  queue_as :default

  MAX_POLLS = 12
  POLL_DELAY = 5.minutes
  STOP_STATUSES = %w[UNPAID REJECTED ERROR SHIPPED CANCELED].freeze

  def perform(order_id, poll_number = 0)
    order = PrintOrder.find_by(id: order_id)
    return unless order && Lulu::Configuration.enabled? && order.user.admin? && order.lulu_print_job_id.present?

    status = Lulu::Client.new.print_job_status(order.lulu_print_job_id)
    order.with_lock do
      order.reload
      return if order.lulu_print_job_id.blank?

      order.update!(provider_status: status.fetch("name"), last_status_checked_at: Time.current)
      unless STOP_STATUSES.include?(order.provider_status) || poll_number >= MAX_POLLS
        self.class.set(wait: POLL_DELAY).perform_later(order.id, poll_number + 1)
      end
    end
  rescue Lulu::Client::RequestError, Lulu::Client::ConfigurationError => error
    order&.update_columns(last_status_checked_at: Time.current,
      failure_message: I18n.t("print_orders.errors.status_refresh", message: error.message))
  end
end
