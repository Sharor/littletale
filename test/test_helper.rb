ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module Minitest::Assertions
  def assert_nothing_raised(*)
    yield
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    VCR.configure do |config|
      config.cassette_library_dir = "test/stubs/vcr_cassettes"
      config.hook_into :faraday

      config.filter_sensitive_data("<BEARER_TOKEN>") do
        Rails.application.credentials.dig(:openai, :api_key)
      end
    end

    # Add more helper methods to be used by all tests here...
  end
end
