# frozen_string_literal: true

require "test_helper"

class Parent::PinResetsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    sign_in @user
  end

  test "recovery sends instructions to the registered account email" do
    assert_enqueued_email_with ParentControlMailer, :pin_reset, params: { control: @control } do
      post parent_pin_reset_url
    end

    assert_redirected_to profile_url
  end

  test "a valid email token replaces the pin and can only be used once" do
    token = @control.generate_token_for(:pin_reset)

    patch parent_pin_reset_url, params: { token: token, parent_control: {
      pin: "7391", pin_confirmation: "7391"
    } }

    assert_redirected_to parent_url
    assert @control.reload.authenticate_pin("7391")

    patch parent_pin_reset_url, params: { token: token, parent_control: {
      pin: "8842", pin_confirmation: "8842"
    } }
    assert_response :unprocessable_content
    assert @control.reload.authenticate_pin("7391")
  end

  test "reset form rejects a mismatched pin" do
    token = @control.generate_token_for(:pin_reset)

    patch parent_pin_reset_url, params: { token: token, parent_control: {
      pin: "7391", pin_confirmation: "7392"
    } }

    assert_response :unprocessable_content
    assert @control.reload.authenticate_pin("4826")
  end
end
