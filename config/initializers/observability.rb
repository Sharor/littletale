require Rails.root.join("lib/observability")

Observability.setup!
Rails.application.config.middleware.use Observability::RequestMetrics::Middleware
