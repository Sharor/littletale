# frozen_string_literal: true

class SubmitPrintOrderJob < ApplicationJob
  queue_as :default

  PRODUCTION_DELAY_MINUTES = 120

  def perform(order_id, expected_content_revision, expected_checkout_revision, submission_uuid)
    submission_attempted = false
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    if order.submission_attempted_at.present?
      return if enqueue_reconciliation(order, expected_content_revision, expected_checkout_revision, submission_uuid)

      return mark_for_review(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    end

    client = Lulu::Client.new
    return unless fresh_quote_confirmed?(order, client, expected_content_revision, expected_checkout_revision,
      submission_uuid)

    claim = claim_submission_attempt(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    return unless claim

    unless enqueue_reconciliation(order, expected_content_revision, expected_checkout_revision, submission_uuid)
      return mark_for_review(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    end
    return if claim == :already_attempted
    submission_attempted = true

    response = client.create_print_job(**submission_payload(order.reload, submission_uuid))
    persist_submission(order, response, expected_content_revision, expected_checkout_revision, submission_uuid)
  rescue Lulu::Client::RequestError => error
    if !submission_attempted
      reset_unattempted_submission(order, expected_content_revision, expected_checkout_revision, submission_uuid,
        I18n.t("print_orders.errors.provider", message: error.message))
    elsif ambiguous_submission_response?(error.status)
      mark_uncertain(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    else
      fail_current(order, expected_content_revision, expected_checkout_revision, submission_uuid,
        I18n.t("print_orders.errors.provider", message: error.message))
    end
  rescue Lulu::Client::ConfigurationError, Lulu::ArtifactUrl::ConfigurationError => error
    message = I18n.t("print_orders.errors.provider", message: error.message)
    if submission_attempted
      fail_current(order, expected_content_revision, expected_checkout_revision, submission_uuid, message)
    else
      reset_unattempted_submission(order, expected_content_revision, expected_checkout_revision, submission_uuid,
        message)
    end
  end

  private

  def ambiguous_submission_response?(status)
    status.zero? || status == 408 || status == 429 || status >= 500
  end

  def current?(order, content_revision, checkout_revision, submission_uuid)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.artifacts_current? && order.quote_current? &&
      order.content_revision == content_revision && order.checkout_revision == checkout_revision &&
      order.submission_uuid == submission_uuid && order.lulu_print_job_id.blank?
  end

  def claim_submission_attempt(order, content_revision, checkout_revision, submission_uuid)
    order.with_lock do
      order.reload
      return false unless current?(order, content_revision, checkout_revision, submission_uuid)
      return :already_attempted if order.submission_attempted_at.present?

      attempted_at = Time.current
      order.update!(
        submission_attempted_at: attempted_at,
        submission_attempts: Array(order.submission_attempts) + [ {
          "external_id" => submission_uuid,
          "attempted_at" => attempted_at.iso8601,
          "outcome" => "pending"
        } ]
      )
      :claimed
    end
  end

  def fresh_quote_confirmed?(order, client, content_revision, checkout_revision, submission_uuid)
    fresh_quote = client.cost_calculation(
      address: order.provider_address,
      line_items: order.provider_line_items,
      shipping_option: order.shipping_option
    ).slice(*QuotePrintOrderJob::QUOTE_KEYS)

    order.with_lock do
      order.reload
      return false unless current?(order, content_revision, checkout_revision, submission_uuid)
      return true if order.quote == fresh_quote

      order.update!(
        workflow_state: "quote_changed",
        quote: fresh_quote,
        quote_revision: checkout_revision,
        quoted_at: Time.current,
        submission_uuid: nil,
        failure_message: I18n.t("print_orders.errors.quote_changed")
      )
      false
    end
  end

  def enqueue_reconciliation(order, content_revision, checkout_revision, submission_uuid)
    job = ReconcilePrintOrderSubmissionJob.set(wait: 15.seconds).perform_later(
      order.id, content_revision, checkout_revision, submission_uuid, 0
    )
    job&.successfully_enqueued? || false
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    false
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
        failure_message: nil,
        submission_attempts: attempts_with_outcome(order, submission_uuid, "submitted",
          "lulu_print_job_id" => response.fetch("id").to_s)
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
        failure_message: I18n.t("print_orders.errors.submission_uncertain"),
        submission_attempts: attempts_with_outcome(order, submission_uuid, "uncertain"))
    end
  end

  def fail_current(order, content_revision, checkout_revision, submission_uuid, message)
    return unless order

    order.with_lock do
      order.reload
      return unless order.content_revision == content_revision && order.checkout_revision == checkout_revision &&
        order.submission_uuid == submission_uuid

      order.update!(workflow_state: "submission_failed", failure_message: message,
        submission_attempts: attempts_with_outcome(order, submission_uuid, "rejected"))
    end
  end

  def reset_unattempted_submission(order, content_revision, checkout_revision, submission_uuid, message)
    return unless order

    order.with_lock do
      order.reload
      return unless order.content_revision == content_revision && order.checkout_revision == checkout_revision &&
        order.submission_uuid == submission_uuid && order.submission_attempted_at.blank?

      order.update!(workflow_state: "quoted", submission_uuid: nil, failure_message: message)
    end
  end

  def mark_for_review(order, content_revision, checkout_revision, submission_uuid)
    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision, submission_uuid)

      order.update!(workflow_state: "submission_needs_review",
        failure_message: I18n.t("print_orders.errors.submission_not_confirmed"),
        submission_attempts: attempts_with_outcome(order, submission_uuid, "needs_review"))
    end
  end

  def attempts_with_outcome(order, submission_uuid, outcome, attributes = {})
    Array(order.submission_attempts).map do |attempt|
      next attempt unless attempt["external_id"] == submission_uuid

      attempt.merge(attributes).merge("outcome" => outcome, "finished_at" => Time.current.iso8601)
    end
  end
end
