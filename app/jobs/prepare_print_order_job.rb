# frozen_string_literal: true

class PreparePrintOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id, expected_revision)
    order = PrintOrder.find_by(id: order_id)
    return unless current?(order, expected_revision)

    result = Lulu::BookletPdf.new(order).render

    order.with_lock do
      order.reload
      return unless current?(order, expected_revision)

      order.interior_pdf.attach(
        io: StringIO.new(result.interior),
        filename: "print-order-#{order.id}-interior-r#{expected_revision}.pdf",
        content_type: "application/pdf"
      )
      order.cover_pdf.attach(
        io: StringIO.new(result.cover),
        filename: "print-order-#{order.id}-cover-r#{expected_revision}.pdf",
        content_type: "application/pdf"
      )
      order.update!(
        artifacts_revision: expected_revision,
        interior_page_count: result.page_count,
        blank_page_count: result.blank_page_count,
        workflow_state: "prepared",
        validation_state: "not_started",
        failure_message: nil
      )
    end
  rescue Lulu::BookletPdf::PageLimitExceeded => error
    fail_current(order, expected_revision, error.message)
  rescue Lulu::BookletPdf::RenderingError, ActiveStorage::Error, Aws::Errors::ServiceError,
         IOError, SystemCallError
    fail_current(order, expected_revision, I18n.t("print_orders.errors.preparation_failed"))
  end

  private

  def current?(order, expected_revision)
    order && Lulu::Configuration.enabled? && order.user.admin? && order.editable? &&
      order.content_revision == expected_revision
  end

  def fail_current(order, expected_revision, message)
    order&.with_lock do
      if current?(order.reload, expected_revision)
        order.update!(workflow_state: "failed", failure_message: message)
      end
    end
  end
end
