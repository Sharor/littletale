class HomeController < ApplicationController
  before_action :check_tutorial, except: %i[index]

  # GET /home or /homes.json
  def index
    I18n.with_locale(:en) do
      @story_samples = StorySample.all
      render :index
    end
  end

  def login
    redirect_to new_user_session_path
  end

  private
end
