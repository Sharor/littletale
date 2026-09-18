# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Admin::CharacterImageAssessmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @owner = users(:one)
    @admin = users(:three)
    @admin.update!(admin: true)
  end

  test "forbids guests and non-administrators from the review queue" do
    get "/admin/character_image_assessments"
    assert_response :forbidden

    sign_in @owner
    get "/admin/character_image_assessments"
    assert_response :forbidden
  end

  test "rejected non-image uploads cannot execute as HTML through the source route" do
    assessment = create_assessment(status: "rejected", prompt: "Invalid upload")
    assessment.photo.attach(io: StringIO.new("<script>alert(1)</script>".b), filename: "image.html", content_type: "text/html")
    sign_in @admin
    get photo_admin_character_image_assessment_path(assessment)
    assert_equal "application/octet-stream", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "filters the queue by moderation status and owner" do
    held = create_assessment(status: "needs_review", prompt: "Held prompt")
    create_assessment(status: "needs_review", prompt: "Another owner's prompt", user: users(:two))
    create_assessment(status: "approved", prompt: "Approved prompt")
    create_assessment(status: "rejected", prompt: "Policy rejection")
    provider_rejected = create_assessment(status: "approved", prompt: "Provider refusal")
    CharacterImageRequest.create!(
      assessment: provider_rejected,
      user: @owner,
      original_character_id: 10_001,
      provider_rejected: true,
      rejection_reason: "The image service declined this request."
    )
    sign_in @admin

    get "/admin/character_image_assessments", params: { status: "needs_review", user_id: @owner.id }

    assert_response :success
    assert_select "h1", "Character image reviews"
    assert_select "nav[aria-label='Review status'] a[aria-current='page']", "Needs review"
    assert_select "article[data-assessment-id='#{held.id}']", 1
    assert_select "article", count: 1

    get "/admin/character_image_assessments", params: { status: "rejected" }

    assert_response :success
    assert_select "article", count: 2
    assert_select "article", text: /Policy rejection/
    assert_select "article", text: /Provider refusal/
  end

  test "links the administrator console to the character image review queue" do
    sign_in @admin

    get "/console"

    assert_response :success
    assert_select "a[href='/admin/character_image_assessments']", "Character image reviews"
  end

  test "shows the submitted evidence, request-specific decisions, and generation outcome" do
    assessment = create_assessment(
      status: "approved",
      prompt: "Exact submitted prompt",
      internal_reason: "flagged violence",
      metadata: { "moderation_id" => "mod_123", "flagged" => true }
    )
    assessment.photo.attach(
      io: StringIO.new("private image bytes".b),
      filename: "source.png",
      content_type: "image/png"
    )
    character = characters(:hernandes)
    request = CharacterImageRequest.create!(
      assessment: assessment,
      user: @owner,
      character: character,
      original_character_id: character.id,
      provider_rejected: true,
      rejection_reason: "The image service declined this request."
    )
    log = ActionLog.create!(user: @owner, trackable: character, action: "setup_illustration")
    CharacterImageGenerationAttempt.create!(
      request: request,
      action_log: log,
      status: "failed",
      failure_metadata: { "provider_request_id" => "img_456" }
    )
    CharacterImageDecision.create!(
      assessment: assessment,
      request: request,
      user: @owner,
      outcome: "rejected",
      source: "provider",
      internal_reason: "generation_moderation_refusal",
      public_reason: "The image service declined this request."
    )
    sign_in @admin

    get "/admin/character_image_assessments/#{assessment.id}"

    assert_response :success
    assert_select "h1", "Character image assessment ##{assessment.id}"
    assert_select "img[src='/admin/character_image_assessments/#{assessment.id}/photo']"
    assert_select "a[href*='rails/active_storage']", count: 0
    assert_select "pre", text: /Exact submitted prompt/
    assert_select "pre", text: /mod_123/
    assert_select "td", "provider"
    assert_select "td", "The image service declined this request."
    assert_select "td", "failed"
    assert_select "pre", text: /img_456/
  end

  test "serves source photos only to administrators" do
    assessment = create_assessment(status: "needs_review")
    assessment.photo.attach(
      io: StringIO.new("private image bytes".b),
      filename: "source.png",
      content_type: "image/png"
    )

    get "/admin/character_image_assessments/#{assessment.id}/photo"
    assert_response :forbidden

    sign_in @owner
    get "/admin/character_image_assessments/#{assessment.id}/photo"
    assert_response :forbidden

    sign_out @owner
    sign_in @admin
    get "/admin/character_image_assessments/#{assessment.id}/photo"

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "private image bytes", response.body
    assert_match(/private/, response.headers.fetch("Cache-Control"))
  end

  test "approves a shared review only once and records the administrator" do
    assessment = create_assessment(status: "needs_review")
    sign_in @admin

    assert_difference -> { assessment.decisions.count }, 1 do
      post "/admin/character_image_assessments/#{assessment.id}/approve",
        params: { decision: { internal_reason: "Suitable family photo" } }
    end

    assert_redirected_to "/admin/character_image_assessments/#{assessment.id}"
    assert_equal "approved", assessment.reload.status
    decision = assessment.decisions.order(:id).last
    assert_equal "admin", decision.source
    assert_equal @admin, decision.reviewer
    assert_equal "Suitable family photo", decision.internal_reason

    assert_no_difference -> { assessment.decisions.count } do
      post "/admin/character_image_assessments/#{assessment.id}/approve",
        params: { decision: { internal_reason: "Duplicate click" } }
    end
    assert_redirected_to "/admin/character_image_assessments/#{assessment.id}"
  end

  test "requires a public reason before rejecting a review" do
    assessment = create_assessment(status: "needs_review")
    sign_in @admin

    assert_no_difference -> { assessment.decisions.count } do
      post "/admin/character_image_assessments/#{assessment.id}/reject",
        params: { decision: { internal_reason: "Private note", public_reason: "" } }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", "Enter a public reason before rejecting this image."
    assert_equal "needs_review", assessment.reload.status

    assert_difference -> { assessment.decisions.count }, 1 do
      post "/admin/character_image_assessments/#{assessment.id}/reject",
        params: {
          decision: {
            internal_reason: "Private note",
            public_reason: "Please upload a clear photo containing one person."
          }
        }
    end

    assert_redirected_to "/admin/character_image_assessments/#{assessment.id}"
    assert_equal "rejected", assessment.reload.status
    assert_equal "Please upload a clear photo containing one person.", assessment.public_reason
    assert_equal @admin, assessment.decisions.order(:id).last.reviewer
  end

  test "only admins can retry unavailable screening and duplicate retries do not enqueue again" do
    assessment = create_assessment(status: "unavailable")
    path = retry_screening_admin_character_image_assessment_path(assessment)
    sign_in @owner
    post path
    assert_response :forbidden
    assert_equal "unavailable", assessment.reload.status
    sign_out @owner
    sign_in @admin
    get admin_character_image_assessments_path(status: "unavailable")
    assert_select "article[data-assessment-id='#{assessment.id}']", 1
    assert_enqueued_with(job: ScreenCharacterImageJob, args: [assessment.id]) { post path }
    assert_redirected_to admin_character_image_assessment_path(assessment)
    assert_equal "checking", assessment.reload.status
    assert_no_enqueued_jobs(only: ScreenCharacterImageJob) { post path }
    assert_empty assessment.decisions
  end

  test "generation retry is scoped to assessment and admin and stale clicks are ignored" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    attempt = request.reload.generation_attempt
    attempt.update!(status: "failed")
    path = retry_generation_admin_character_image_assessment_path(request.assessment)
    payload = { request_id: request.id, attempt_version: attempt.updated_at.iso8601(6) }
    post path, params: payload
    assert_response :forbidden
    sign_in @owner
    post path, params: payload
    assert_response :forbidden
    sign_out @owner
    sign_in @admin
    get admin_character_image_assessment_path(request.assessment)
    assert_select "input[value='Retry generation']"
    assert_enqueued_with(job: GenerateCharacterImageJob, args: [attempt.id]) { post path, params: payload }
    assert_no_enqueued_jobs(only: GenerateCharacterImageJob) { post path, params: payload }
    other = create_assessment(status: "approved")
    post retry_generation_admin_character_image_assessment_path(other), params: payload
    assert_response :not_found
  end

  test "an administrator can release a failed character credit" do
    grant_paid_bundle
    character = @owner.characters.create!(name: "Funded character", age: 8, gender: "Girl", ethnicity: "White",
      hair_color: "Brown", hair_style: "Long", eye_color: "Blue", roles: [ "Hero" ], creation_mode: "form")
    request = CharacterImageRequest.submit!(character)
    request.generation_attempt.update!(status: "failed")
    reservation = request.character_credit_reservations.held.first
    sign_in @admin

    get admin_character_image_assessment_path(request.assessment)
    assert_select "[data-character-funding='held']", text: /credit reserved/i
    assert_select "form[action='#{release_character_credit_admin_character_image_assessment_path(request.assessment)}']"

    assert_difference("@owner.reload.available_character_credits", 1) do
      post release_character_credit_admin_character_image_assessment_path(request.assessment),
        params: { request_id: request.id }
    end

    assert_equal "released", reservation.reload.status
    assert_equal @admin, reservation.released_by
  end

  test "retrying screening reacquires a released paid character credit" do
    grant_paid_bundle
    character = @owner.characters.create!(name: "Screened character", age: 8, gender: "Girl", ethnicity: "White",
      hair_color: "Brown", hair_style: "Long", eye_color: "Blue", roles: [ "Hero" ], creation_mode: "form")
    character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png",
      content_type: "image/png")
    request = CharacterImageRequest.submit!(character)
    request.assessment.update!(status: "unavailable")
    request.character_credit_reservations.held.first.release!(by: @admin, reason: "admin_released_failed_character")
    sign_in @admin

    post retry_screening_admin_character_image_assessment_path(request.assessment)

    assert_redirected_to admin_character_image_assessment_path(request.assessment)
    assert_predicate request.character_credit_reservations.held, :exists?
    assert_equal 4, @owner.reload.available_character_credits
  end

  test "a screening retry queue failure returns the reacquired character credit" do
    grant_paid_bundle
    character = @owner.characters.create!(name: "Unqueued character", age: 8, gender: "Girl", ethnicity: "White",
      hair_color: "Brown", hair_style: "Long", eye_color: "Blue", roles: [ "Hero" ], creation_mode: "form")
    character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png",
      content_type: "image/png")
    request = CharacterImageRequest.submit!(character)
    request.assessment.update!(status: "unavailable")
    request.character_credit_reservations.held.first.release!(by: @admin,
      reason: "admin_released_failed_character")
    failed_job = Struct.new(:successfully_enqueued?).new(false)
    sign_in @admin

    ScreenCharacterImageJob.stub(:perform_later, failed_job) do
      post retry_screening_admin_character_image_assessment_path(request.assessment)
    end

    assert_equal "unavailable", request.assessment.reload.status
    assert_not_predicate request.character_credit_reservations.held, :exists?
    assert_equal 5, @owner.reload.available_character_credits
  end

  test "an administrator cannot release a credit from completed generation" do
    grant_paid_bundle
    character = @owner.characters.create!(name: "Completed character", age: 8, gender: "Girl", ethnicity: "White",
      hair_color: "Brown", hair_style: "Long", eye_color: "Blue", roles: [ "Hero" ], creation_mode: "form")
    request = CharacterImageRequest.submit!(character)
    request.generation_attempt.update!(status: "completed")
    reservation = request.character_credit_reservations.held.first
    sign_in @admin

    get admin_character_image_assessment_path(request.assessment)
    assert_select "form[action='#{release_character_credit_admin_character_image_assessment_path(request.assessment)}']", count: 0

    assert_no_changes("reservation.reload.status") do
      post release_character_credit_admin_character_image_assessment_path(request.assessment),
        params: { request_id: request.id }
    end

    assert_equal "held", reservation.reload.status
    assert_equal 4, @owner.reload.available_character_credits
  end

  test "an admin retry queue failure keeps funding already held for the failed request" do
    grant_paid_bundle
    character = @owner.characters.create!(name: "Held retry", age: 8, gender: "Girl", ethnicity: "White",
      hair_color: "Brown", hair_style: "Long", eye_color: "Blue", roles: [ "Hero" ], creation_mode: "form")
    request = CharacterImageRequest.submit!(character)
    attempt = request.generation_attempt
    attempt.update!(status: "failed")
    reservation = request.character_credit_reservations.held.first
    failed_job = Struct.new(:successfully_enqueued?).new(false)
    sign_in @admin

    GenerateCharacterImageJob.stub(:perform_later, failed_job) do
      post retry_generation_admin_character_image_assessment_path(request.assessment), params: {
        request_id: request.id,
        attempt_version: attempt.updated_at.iso8601(6)
      }
    end

    assert_equal "held", reservation.reload.status
    assert_equal 4, @owner.reload.available_character_credits
    assert_equal "failed", attempt.reload.status
  end

  private


  def create_assessment(status:, prompt: "A character portrait", user: @owner, internal_reason: nil, metadata: {})
    CharacterImageAssessment.create!(
      user: user,
      fingerprint: SecureRandom.hex(16),
      prompt: prompt,
      generation_model: "gpt-image-1",
      policy_version: CharacterImageAssessment::POLICY_VERSION,
      status: status,
      internal_reason: internal_reason,
      metadata: metadata
    )
  end

  def grant_paid_bundle
    purchase = @owner.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_admin_character", payment_intent_id: "pi_admin_character",
      stripe_customer_id: "cus_admin_character", price_id: "price_test", amount_total: 2500, currency: "dkk")
  end
end
