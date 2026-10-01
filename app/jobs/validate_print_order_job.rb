# frozen_string_literal: true

class ValidatePrintOrderJob < ApplicationJob
  queue_as :default

  MAX_POLLS = 6
  POLL_DELAY = 15.seconds
  SHIPPING_KEYS = %w[
    level currency cost_excl_tax min_delivery_date max_delivery_date min_dispatch_date max_dispatch_date
    total_days_min total_days_max traceable
  ].freeze

  def perform(order_id, expected_content_revision, expected_checkout_revision, poll_number = 0)
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_content_revision, expected_checkout_revision)

    client = Lulu::Client.new
    details = order.validation_details
    if details["interior_id"].present? && details["cover_id"].present?
      interior = client.interior_validation(details.fetch("interior_id"))
      cover = client.cover_validation(details.fetch("cover_id"))
    else
      interior, cover, dimensions = start_validations(order, client)
      return unless persist_started(order, expected_content_revision, expected_checkout_revision, interior, cover, dimensions)
    end

    statuses = validation_statuses(interior, cover)
    if statuses.values.any? { |result| result["status"] == "ERROR" }
      return fail_current(order, expected_content_revision, expected_checkout_revision,
        validation_error_message(statuses))
    end

    if statuses.values.all? { |result| result["status"] == "NORMALIZED" }
      store_shipping_options(order, client, expected_content_revision, expected_checkout_revision, statuses)
    elsif poll_number >= MAX_POLLS
      fail_current(order, expected_content_revision, expected_checkout_revision,
        I18n.t("print_orders.errors.validation_timeout"))
    else
      self.class.set(wait: POLL_DELAY).perform_later(
        order.id, expected_content_revision, expected_checkout_revision, poll_number + 1
      )
    end
  rescue Lulu::Client::RequestError, Lulu::Client::ConfigurationError,
         Lulu::ArtifactUrl::ConfigurationError => error
    fail_current(order, expected_content_revision, expected_checkout_revision,
      I18n.t("print_orders.errors.provider", message: error.message))
  end

  private

  def current?(order, content_revision, checkout_revision)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.editable? && order.artifacts_current? &&
      order.content_revision == content_revision && order.checkout_revision == checkout_revision
  end

  def start_validations(order, client)
    interior = client.create_interior_validation(
      source_url: Lulu::ArtifactUrl.for(order:, kind: :interior),
      pod_package_id: order.pod_package_id
    )
    dimensions = client.cover_dimensions(
      pod_package_id: order.pod_package_id,
      interior_page_count: order.interior_page_count
    )
    verify_cover_dimensions!(dimensions)
    cover = client.create_cover_validation(
      source_url: Lulu::ArtifactUrl.for(order:, kind: :cover),
      pod_package_id: order.pod_package_id,
      interior_page_count: order.interior_page_count
    )
    [ interior, cover, dimensions ]
  end

  def verify_cover_dimensions!(dimensions)
    expected_width = format("%.3f", Lulu::BookletPdf::COVER_SIZE.first / Lulu::BookletPdf::POINTS_PER_INCH)
    expected_height = format("%.3f", Lulu::BookletPdf::COVER_SIZE.last / Lulu::BookletPdf::POINTS_PER_INCH)
    return if dimensions["unit"] == "inch" && dimensions["width"] == expected_width &&
      dimensions["height"] == expected_height

    raise Lulu::Client::RequestError.new(status: 422,
      details: I18n.t("print_orders.errors.cover_dimensions"))
  end

  def persist_started(order, content_revision, checkout_revision, interior, cover, dimensions)
    order.with_lock do
      order.reload
      return false unless current?(order, content_revision, checkout_revision)

      order.update!(
        workflow_state: "validating",
        validation_state: "validating",
        cover_dimensions: dimensions.slice("width", "height", "unit"),
        validation_details: revision_details(content_revision, checkout_revision).merge(
          "interior_id" => interior.fetch("id"),
          "cover_id" => cover.fetch("id"),
          "interior_status" => interior["status"],
          "cover_status" => cover["status"],
          "interior_errors" => sanitized_errors(interior["errors"]),
          "cover_errors" => sanitized_errors(cover["errors"])
        ),
        failure_message: nil
      )
    end
    true
  end

  def validation_statuses(interior, cover)
    {
      "interior" => { "status" => interior["status"], "errors" => sanitized_errors(interior["errors"]) },
      "cover" => { "status" => cover["status"], "errors" => sanitized_errors(cover["errors"]) }
    }
  end

  def sanitized_errors(errors)
    Array(errors).map { |error| Lulu::Client::RequestError.sanitize(error).to_s }
  end

  def validation_error_message(statuses)
    errors = statuses.flat_map { |kind, result| result["errors"].map { |message| "#{kind}: #{message}" } }
    I18n.t("print_orders.errors.validation_rejected", message: errors.join(", ").presence || "Lulu rejected a PDF.")
  end

  def store_shipping_options(order, client, content_revision, checkout_revision, statuses)
    options = client.shipping_options(
      address: order.provider_address,
      line_items: order.provider_line_items,
      currency: order.quote_currency
    ).map { |option| option.slice(*SHIPPING_KEYS) }
    if options.empty?
      return fail_current(order, content_revision, checkout_revision,
        I18n.t("print_orders.errors.no_shipping_options"))
    end

    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision)

      order.update!(
        workflow_state: "selecting_shipping",
        validation_state: "validated",
        shipping_options: options,
        validation_details: revision_details(content_revision, checkout_revision).merge(
          "interior_id" => order.validation_details["interior_id"],
          "cover_id" => order.validation_details["cover_id"],
          "interior_status" => statuses.fetch("interior").fetch("status"),
          "cover_status" => statuses.fetch("cover").fetch("status"),
          "interior_errors" => statuses.fetch("interior").fetch("errors"),
          "cover_errors" => statuses.fetch("cover").fetch("errors")
        ),
        failure_message: nil
      )
    end
  end

  def fail_current(order, content_revision, checkout_revision, message)
    return unless order

    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision)

      order.update!(workflow_state: "failed", validation_state: "failed", failure_message: message)
    end
  end

  def revision_details(content_revision, checkout_revision)
    { "content_revision" => content_revision, "checkout_revision" => checkout_revision }
  end
end
