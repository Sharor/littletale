# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Users::OmniauthCallbacksControllerTest < ActionController::TestCase
  tests Users::OmniauthCallbacksController
  include Devise::Test::ControllerHelpers

  teardown do
    Current.reset
  end

  test "signs in a user returned by the Google OAuth callback" do
    oauth_payload = { "provider" => "google_oauth2", "uid" => "google-user-id" }
    user = Struct.new(:persisted?).new(true)

    visitor = Minitest::Mock.new
    visitor.expect :presence, visitor
    visitor.expect :update!, true, [], user: user
    events = Minitest::Mock.new
    events.expect :create, true do |attributes|
      assert_equal "GET", attributes[:method]
      assert_kind_of String, attributes[:path]
      assert_kind_of String, attributes[:params]
    end
    visitor.expect :events, events

    @request.env["omniauth.auth"] = oauth_payload
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @controller.define_singleton_method(:devise_mapping) { Devise.mappings[:user] }

    @controller.stub :set_current_visitor, -> { Current.visitor = visitor } do
      User.stub :from_omniauth, ->(payload) { assert_equal oauth_payload, payload; user } do
        @controller.stub :sign_in_and_redirect, ->(authenticated_user, event:) {
          assert_same user, authenticated_user
          assert_equal :authentication, event
          @controller.redirect_to "/"
        } do
          get :google_oauth2
        end
      end
    end

    assert_redirected_to "/"
    visitor.verify
    events.verify
  end

  test "signs in a user returned by the Microsoft OAuth callback" do
    oauth_payload = { "provider" => "microsoft_v2_auth", "uid" => "microsoft-user-id" }
    user = Struct.new(:persisted?).new(true)

    visitor = Minitest::Mock.new
    visitor.expect :presence, visitor
    visitor.expect :update!, true, [], user: user
    events = Minitest::Mock.new
    events.expect :create, true do |attributes|
      assert_equal "GET", attributes[:method]
      assert_kind_of String, attributes[:path]
      assert_kind_of String, attributes[:params]
    end
    visitor.expect :events, events

    @request.env["omniauth.auth"] = oauth_payload
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @controller.define_singleton_method(:devise_mapping) { Devise.mappings[:user] }

    @controller.stub :set_current_visitor, -> { Current.visitor = visitor } do
      User.stub :from_omniauth, ->(payload) { assert_equal oauth_payload, payload; user } do
        @controller.stub :sign_in_and_redirect, ->(authenticated_user, event:) {
          assert_same user, authenticated_user
          assert_equal :authentication, event
          @controller.redirect_to "/"
        } do
          get :microsoft_v2_auth
        end
      end
    end

    assert_redirected_to "/"
    assert_equal "Successfully authenticated from Microsoft account.", flash[:notice]
    visitor.verify
    events.verify
  end
end
