# frozen_string_literal: true

class QuotePrintOrderJob < ApplicationJob
  queue_as :default

  QUOTE_KEYS = %w[
    currency total_cost_excl_tax total_cost_incl_tax total_discount_amount total_tax shipping_cost
    fulfillment_cost line_item_costs fees
  ].freeze

  def perform(order_id, expected_content_revision, expected_checkout_revision, shipping_option)
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_content_revision, expected_checkout_revision, shipping_option)

    quote = Lulu::Client.new.cost_calculation(
      address: order.provider_address,
      line_items: order.provider_line_items,
      shipping_option:
    ).slice(*QUOTE_KEYS)

    order.with_lock do
      order.reload
      return unless current?(order, expected_content_revision, expected_checkout_revision, shipping_option)

      order.update!(
        workflow_state: "quoted",
        shipping_option:,
        quote:,
        quote_revision: expected_checkout_revision,
        quoted_at: Time.current,
        failure_message: nil
      )
    end
  rescue Lulu::Client::RequestError, Lulu::Client::ConfigurationError => error
    fail_current(order, expected_content_revision, expected_checkout_revision, shipping_option,
      I18n.t("print_orders.errors.provider", message: error.message))
  end

  private

  def current?(order, content_revision, checkout_revision, shipping_option)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.editable? && order.artifacts_current? &&
      order.validation_state == "validated" && order.content_revision == content_revision &&
      order.checkout_revision == checkout_revision &&
      order.shipping_options.any? { |option| option["level"] == shipping_option }
  end

  def fail_current(order, content_revision, checkout_revision, shipping_option, message)
    return unless order

    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision, shipping_option)

      order.update!(workflow_state: "failed", failure_message: message)
    end
  end
end
