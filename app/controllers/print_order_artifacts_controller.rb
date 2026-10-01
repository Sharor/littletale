# frozen_string_literal: true

class PrintOrderArtifactsController < ApplicationController
  def show
    payload = Lulu::ArtifactUrl.verify(params[:token])
    kind = params[:kind].to_s
    order = PrintOrder.find(payload.fetch(:order_id))
    return head :not_found unless payload.fetch(:kind) == kind
    return head :not_found unless payload.fetch(:revision) == order.content_revision && order.artifacts_current?

    attachment = kind == "interior" ? order.interior_pdf : order.cover_pdf
    send_data attachment.download,
      filename: "print-order-#{order.id}-#{kind}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, KeyError
    head :not_found
  end
end
