# frozen_string_literal: true

require "test_helper"

class BrandingTest < ActiveSupport::TestCase
  test "the Rails application uses the MinorTale identity" do
    assert_equal "MinorTale", Rails.application.class.module_parent_name
    assert_equal "MinorTale", Rails.application.config.x.brand.name
    assert_equal "minortale.com", Rails.application.config.x.brand.canonical_host
    assert_equal "MinorTale <hello@minortale.com>", Rails.application.config.x.brand.mailer_sender
  end
end
