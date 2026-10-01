# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class Lulu::ClientTest < ActiveSupport::TestCase
  BASE_URL = "https://api.sandbox.lulu.com"
  TOKEN_URL = "#{BASE_URL}/auth/realms/glasstree/protocol/openid-connect/token"

  setup do
    VCR.turn_off!(ignore_cassettes: true)
    @now = Time.utc(2026, 10, 1, 10)
    @client = Lulu::Client.new(
      client_id: "sandbox-client",
      client_secret: "sandbox-secret",
      clock: -> { @now }
    )
  end

  teardown do
    VCR.turn_on!
  end

  test "authenticates with client credentials and reuses an unexpired token" do
    token_request = stub_token(token: "token-one", expires_in: 300)
    interior_request = stub_request(:post, "#{BASE_URL}/validate-interior/")
      .with(
        headers: { "Authorization" => "Bearer token-one", "Content-Type" => "application/json" },
        body: { source_url: "https://assets.example.test/interior.pdf", pod_package_id: PrintOrder::POD_PACKAGE_ID }.to_json
      )
      .to_return(status: 201, headers: json_headers,
        body: { id: 17, status: "NORMALIZING", errors: [] }.to_json)
    dimensions_request = stub_request(:post, "#{BASE_URL}/cover-dimensions/")
      .with(
        headers: { "Authorization" => "Bearer token-one", "Content-Type" => "application/json" },
        body: { pod_package_id: PrintOrder::POD_PACKAGE_ID, interior_page_count: 4, unit: "inch" }.to_json
      )
      .to_return(status: 201, headers: json_headers,
        body: { width: "10.250", height: "8.250", unit: "inch" }.to_json)

    assert_equal 17, @client.create_interior_validation(
      source_url: "https://assets.example.test/interior.pdf",
      pod_package_id: PrintOrder::POD_PACKAGE_ID
    ).fetch("id")
    assert_equal "10.250", @client.cover_dimensions(
      pod_package_id: PrintOrder::POD_PACKAGE_ID,
      interior_page_count: 4
    ).fetch("width")

    assert_requested token_request, times: 1
    assert_requested interior_request
    assert_requested dimensions_request
  end

  test "renews the bearer token before it expires" do
    token_request = stub_request(:post, TOKEN_URL)
      .with(body: { grant_type: "client_credentials" })
      .to_return(
        { status: 200, headers: json_headers,
          body: { access_token: "short-token", expires_in: 31, token_type: "Bearer" }.to_json },
        { status: 200, headers: json_headers,
          body: { access_token: "fresh-token", expires_in: 300, token_type: "Bearer" }.to_json }
      )
    stub_request(:get, "#{BASE_URL}/validate-interior/8/")
      .to_return(status: 200, headers: json_headers,
        body: { id: 8, status: "NORMALIZED", errors: [] }.to_json)

    @client.interior_validation(8)
    @now += 2.seconds
    @client.interior_validation(8)

    assert_requested token_request, times: 2
  end

  test "uses Lulu's distinct shipping and cost address schemas" do
    stub_token
    shipping_request = stub_request(:post, "#{BASE_URL}/shipping-options/")
      .with(body: {
        currency: "EUR",
        line_items: [ { page_count: 4, pod_package_id: PrintOrder::POD_PACKAGE_ID, quantity: 1 } ],
        shipping_address: {
          name: "A Reader", street1: "Story Lane 4", street2: nil, city: "Copenhagen",
          postcode: "2100", country: "DK", state: nil, phone_number: "+45 12345678"
        }
      }.to_json)
      .to_return(status: 200, headers: json_headers,
        body: [ { level: "MAIL", currency: "EUR", cost_excl_tax: "4.25" } ].to_json)
    cost_request = stub_request(:post, "#{BASE_URL}/print-job-cost-calculations/")
      .with(body: {
        shipping_option: "MAIL",
        line_items: [ { page_count: 4, pod_package_id: PrintOrder::POD_PACKAGE_ID, quantity: 1 } ],
        shipping_address: {
          name: "A Reader", street1: "Story Lane 4", street2: nil, city: "Copenhagen",
          postcode: "2100", country_code: "DK", state_code: nil,
          email: "reader@example.com", phone_number: "+45 12345678"
        }
      }.to_json)
      .to_return(status: 201, headers: json_headers, body: {
        currency: "EUR", total_cost_incl_tax: "14.80", total_tax: "2.96",
        shipping_cost: { total_cost_incl_tax: "5.00" }
      }.to_json)
    address = {
      name: "A Reader", street1: "Story Lane 4", street2: nil, city: "Copenhagen", postcode: "2100",
      country_code: "DK", state_code: nil, email: "reader@example.com", phone_number: "+45 12345678"
    }
    line_items = [ { page_count: 4, pod_package_id: PrintOrder::POD_PACKAGE_ID, quantity: 1 } ]

    options = @client.shipping_options(address:, line_items:, currency: "EUR")
    quote = @client.cost_calculation(address:, line_items:, shipping_option: "MAIL")

    assert_equal "MAIL", options.first.fetch("level")
    assert_equal "14.80", quote.fetch("total_cost_incl_tax")
    assert_requested shipping_request
    assert_requested cost_request
  end

  test "creates and retrieves cover validation records" do
    stub_token
    create_request = stub_request(:post, "#{BASE_URL}/validate-cover/")
      .with(body: {
        source_url: "https://assets.example.test/cover.pdf",
        pod_package_id: PrintOrder::POD_PACKAGE_ID,
        interior_page_count: 4
      }.to_json)
      .to_return(status: 201, headers: json_headers,
        body: { id: 22, status: "NORMALIZING", errors: [] }.to_json)
    read_request = stub_request(:get, "#{BASE_URL}/validate-cover/22/")
      .to_return(status: 200, headers: json_headers,
        body: { id: 22, status: "NORMALIZED", errors: [] }.to_json)

    created = @client.create_cover_validation(
      source_url: "https://assets.example.test/cover.pdf",
      pod_package_id: PrintOrder::POD_PACKAGE_ID,
      interior_page_count: 4
    )
    completed = @client.cover_validation(created.fetch("id"))

    assert_equal "NORMALIZING", created.fetch("status")
    assert_equal "NORMALIZED", completed.fetch("status")
    assert_requested create_request
    assert_requested read_request
  end

  test "refreshes once and retries an API request after a 401" do
    token_request = stub_request(:post, TOKEN_URL)
      .to_return(
        { status: 200, headers: json_headers,
          body: { access_token: "expired-token", expires_in: 300 }.to_json },
        { status: 200, headers: json_headers,
          body: { access_token: "replacement-token", expires_in: 300 }.to_json }
      )
    validation_request = stub_request(:get, "#{BASE_URL}/validate-interior/9/")
      .with(headers: { "Authorization" => "Bearer expired-token" })
      .to_return(status: 401, headers: json_headers, body: { detail: "Expired" }.to_json)
    replacement_request = stub_request(:get, "#{BASE_URL}/validate-interior/9/")
      .with(headers: { "Authorization" => "Bearer replacement-token" })
      .to_return(status: 200, headers: json_headers,
        body: { id: 9, status: "NORMALIZED", errors: [] }.to_json)

    assert_equal "NORMALIZED", @client.interior_validation(9).fetch("status")
    assert_requested token_request, times: 2
    assert_requested validation_request
    assert_requested replacement_request
  end

  test "converts a network timeout to a sanitized request error" do
    stub_token
    stub_request(:get, "#{BASE_URL}/validate-cover/22/").to_timeout

    error = assert_raises(Lulu::Client::RequestError) { @client.cover_validation(22) }

    assert_equal 0, error.status
    assert_equal "The Lulu sandbox did not respond.", error.details
  end

  test "creates a one-copy print job with Lulu's printable normalization schema" do
    stub_token
    payload = {
      external_id: "submission-uuid",
      contact_email: "admin@example.com",
      line_items: [ {
        external_id: "submission-uuid-1",
        printable_normalization: {
          cover: { source_url: "https://assets.example.test/cover.pdf" },
          interior: { source_url: "https://assets.example.test/interior.pdf" },
          pod_package_id: PrintOrder::POD_PACKAGE_ID
        },
        quantity: 1,
        title: "Printed moon"
      } ],
      production_delay: 120,
      shipping_address: {
        name: "A Reader", street1: "Story Lane 4", street2: nil, city: "Copenhagen", postcode: "2100",
        country_code: "DK", state_code: nil, email: "reader@example.com", phone_number: "+45 12345678"
      },
      shipping_level: "MAIL"
    }
    create_request = stub_request(:post, "#{BASE_URL}/print-jobs/")
      .with(body: payload.to_json)
      .to_return(status: 201, headers: json_headers,
        body: { id: 551, external_id: "submission-uuid", status: { name: "UNPAID" } }.to_json)

    result = @client.create_print_job(**payload)

    assert_equal 551, result.fetch("id")
    assert_equal "UNPAID", result.dig("status", "name")
    assert_requested create_request
  end

  test "finds an exact external id and retrieves print-job status" do
    stub_token
    list_request = stub_request(:get, "#{BASE_URL}/print-jobs/")
      .with(query: hash_including("search" => "submission-uuid"))
      .to_return(status: 200, headers: json_headers, body: {
        count: 2,
        results: [
          { id: 551, external_id: "submission-uuid-old", status: { name: "UNPAID" } },
          { id: 552, external_id: "submission-uuid", status: { name: "CREATED" } }
        ]
      }.to_json)
    status_request = stub_request(:get, "#{BASE_URL}/print-jobs/552/status/")
      .to_return(status: 200, headers: json_headers,
        body: { name: "UNPAID", changed: "2026-10-01T12:00:00Z", message: "Payment required" }.to_json)

    match = @client.find_print_job_by_external_id("submission-uuid")
    status = @client.print_job_status(match.fetch("id"))

    assert_equal 552, match.fetch("id")
    assert_equal "UNPAID", status.fetch("name")
    assert_requested list_request
    assert_requested status_request
  end

  test "raises a sanitized provider error" do
    stub_token
    stub_request(:post, "#{BASE_URL}/cover-dimensions/")
      .to_return(status: 400, headers: json_headers,
        body: { interior_page_count: [ "Unsupported page count." ] }.to_json)

    error = assert_raises(Lulu::Client::RequestError) do
      @client.cover_dimensions(pod_package_id: PrintOrder::POD_PACKAGE_ID, interior_page_count: 2)
    end

    assert_equal 400, error.status
    assert_equal({ "interior_page_count" => [ "Unsupported page count." ] }, error.details)
    assert_not_includes error.message, "sandbox-secret"
  end

  test "redacts delivery details and signed URLs from provider errors" do
    stub_token
    signed_url = "https://assets.example.test/lulu-files/private-token/interior.pdf"
    stub_request(:post, "#{BASE_URL}/cover-dimensions/")
      .to_return(status: 400, headers: json_headers, body: {
        shipping_address: {
          name: "A Reader", street1: "Story Lane 4", city: "Copenhagen",
          email: "reader@example.com", phone_number: "+45 12345678"
        },
        source_url: signed_url,
        detail: "Could not fetch #{signed_url} for reader@example.com"
      }.to_json)

    error = assert_raises(Lulu::Client::RequestError) do
      @client.cover_dimensions(pod_package_id: PrintOrder::POD_PACKAGE_ID, interior_page_count: 4)
    end

    [ "A Reader", "Story Lane 4", "Copenhagen", "reader@example.com", "+45 12345678",
      "private-token", signed_url ].each do |secret|
      assert_not_includes error.details.to_s, secret
      assert_not_includes error.message, secret
    end
    assert_includes error.message, "[FILTERED]"
  end

  private

  def stub_token(token: "sandbox-token", expires_in: 300)
    stub_request(:post, TOKEN_URL)
      .with(
        headers: { "Authorization" => "Basic #{Base64.strict_encode64("sandbox-client:sandbox-secret")}" },
        body: { grant_type: "client_credentials" }
      )
      .to_return(status: 200, headers: json_headers,
        body: { access_token: token, expires_in:, token_type: "Bearer" }.to_json)
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end
end
