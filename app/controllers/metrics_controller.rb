require "prometheus/client/formats/text"

class MetricsController < ActionController::Metal
  include ActionController::Rendering

  def show
    return self.status = :unauthorized unless authorized?

    Observability.refresh_queue_metrics
    self.content_type = Prometheus::Client::Formats::Text::CONTENT_TYPE
    self.response_body = Prometheus::Client::Formats::Text.marshal(Observability.registry)
  end

  private
    def authorized?
      expected = ENV["METRICS_BEARER_TOKEN"].to_s
      supplied = request.authorization.to_s.delete_prefix("Bearer ")
      expected.present? && supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
    end
end
