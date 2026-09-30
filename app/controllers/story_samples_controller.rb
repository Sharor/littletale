# frozen_string_literal: true

class StorySamplesController < ApplicationController
  skip_before_action :check_tutorial
  skip_before_action :enforce_trial_access

  def show
    @story = StorySample.find(params[:id])
    return head :not_found unless @story

    I18n.with_locale(:en) { render :show }
  end
end
