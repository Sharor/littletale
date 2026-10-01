# frozen_string_literal: true

class ReconcilePrintOrderSubmissionJob < ApplicationJob
  queue_as :default

  MAX_SEARCHES = 6
  SEARCH_DELAY = 30.seconds

  def perform(order_id, expected_content_revision, expected_checkout_revision, submission_uuid, search_number = 0)
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_content_revision, expected_checkout_revision, submission_uuid)

    match = Lulu::Client.new.find_print_job_by_external_id(submission_uuid)
    if match
      persist_match(order, match, expected_content_revision, expected_checkout_revision, submission_uuid)
    elsif search_number >= MAX_SEARCHES
      mark_for_review(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    else
      schedule_search(order, expected_content_revision, expected_checkout_revision, submission_uuid, search_number + 1)
    end
  rescue Lulu::Client::RequestError, Lulu::Client::ConfigurationError
    if search_number >= MAX_SEARCHES
      mark_for_review(order, expected_content_revision, expected_checkout_revision, submission_uuid)
    else
      schedule_search(order, expected_content_revision, expected_checkout_revision, submission_uuid, search_number + 1)
    end
  end

  private

  def current?(order, content_revision, checkout_revision, submission_uuid)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.content_revision == content_revision &&
      order.checkout_revision == checkout_revision && order.submission_uuid == submission_uuid &&
      order.submission_attempted_at.present? && order.workflow_state.in?(%w[submitting submission_uncertain]) &&
      order.lulu_print_job_id.blank?
  end

  def persist_match(order, match, content_revision, checkout_revision, submission_uuid)
    order.with_lock do
      order.reload
      return unless current?(order, content_revision, checkout_revision, submission_uuid)

      order.update!(
        workflow_state: "submitted",
        lulu_print_job_id: match.fetch("id").to_s,
        provider_status: match.dig("status", "name") || "CREATED",
        submitted_at: Time.current,
        submission_uncertain_at: nil,
        last_status_checked_at: Time.current,
        failure_message: nil,
        submission_attempts: attempts_with_outcome(order, submission_uuid, "submitted",
          "lulu_print_job_id" => match.fetch("id").to_s)
      )
      RefreshPrintOrderStatusJob.set(wait: 30.seconds).perform_later(order.id, 0)
    end
  end

  def schedule_search(order, content_revision, checkout_revision, submission_uuid, next_search)
    return unless current?(order.reload, content_revision, checkout_revision, submission_uuid)

    self.class.set(wait: SEARCH_DELAY).perform_later(
      order.id, content_revision, checkout_revision, submission_uuid, next_search
    )
  end

  def mark_for_review(order, content_revision, checkout_revision, submission_uuid)
    return unless order

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
