# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial
end
