module HealthChecks
  Result = Data.define(:name, :status, :message, :checked_at, :duration_ms) do
    def to_h
      super.transform_keys(&:to_s)
    end
  end
end
