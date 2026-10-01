# frozen_string_literal: true

class SubmitPrintOrderJob < ApplicationJob
  queue_as :default

  PRODUCTION_DELAY_MINUTES = 120

  def perform(order_id, expected_content_revision, expected_checkout_revision, submission_uuid)
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_content_revision, expected_checkout_revision, submission_uuid)

    response = Lulu::Client.new.create_print_job(**submission_payload(order, submission_uuid))
    persist_submission(order, response, expected_content_revision, expected_checkout_revision, submission_uuid)
  rescue Lulu::Client::RequestError => error
    if error.status.zero?
      mark_uncertain(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    else
      fail_current(order, expected_content_revision, expected_checkout_revision, submission_uuid,
        I18n.t("print_orders.errors.provider", message: error.message))
    end
  rescue Lulu::Client::ConfigurationError, Lulu::ArtifactUrl::ConfigurationError => error
    fail_current(order, expected_content_revision, expected_checkout_revision, submission_uuid,
      I18n.t("print_orders.errors.provider", message: error.message))
  end

  private

  def current?(order, content_revision, checkout_revision, submission_uuid)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.artifacts_current? && order.quote_current? &&
      order.content_revision == content_revision && order.checkout_revision == checkout_revision &&
      order.submission_uuid == submission_uuid && order.lulu_print_job_id.blank?
  end

  def submission_payload(order, submission_uuid)
    {
      external_id: submission_uuid,
      contact_email: order.user.email,
      line_items: [ {
        external_id: "#{submission_uuid}-1",
        printable_normalization: {
          cover: { source_url: Lulu::ArtifactUrl.for(order:, kind: :cover) },
          interior: { source_url: Lulu::ArtifactUrl.for(order:, kind: :interior) },
          pod_package_id: order.pod_package_id
        },
        quantity: 1,
        title: order.title
      } ],
      production_delay: PRODUCTION_DELAY_MINUTES,
      shipping_address: order.provider_address,
      shipping_level: order.shipping_option
    }
  end

  def persist_submission(order, response, content_revision, checkout_revision, submission_uuid)
    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision, submission_uuid)

      order.update!(
        workflow_state: "submitted",
        lulu_print_job_id: response.fetch("id").to_s,
        provider_status: response.dig("status", "name") || "CREATED",
        submitted_at: Time.current,
        submission_uncertain_at: nil,
        last_status_checked_at: Time.current,
        failure_message: nil
      )
      RefreshPrintOrderStatusJob.set(wait: 30.seconds).perform_later(order.id, 0)
    end
  end

  def mark_uncertain(order, content_revision, checkout_revision, submission_uuid)
    return unless order

    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision, submission_uuid)

      order.update!(workflow_state: "submission_uncertain", submission_uncertain_at: Time.current,
        failure_message: I18n.t("print_orders.errors.submission_uncertain"))
      ReconcilePrintOrderSubmissionJob.set(wait: 15.seconds).perform_later(
        order.id, content_revision, checkout_revision, submission_uuid, 0
      )
    end
  end

  def fail_current(order, content_revision, checkout_revision, submission_uuid, message)
    return unless order

    order.with_lock do
      order.reload
      return unless order.content_revision == content_revision && order.checkout_revision == checkout_revision &&
        order.submission_uuid == submission_uuid

      order.update!(workflow_state: "submission_failed", failure_message: message)
    end
  end
end
