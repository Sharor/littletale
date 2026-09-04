class HomeController < ApplicationController
  before_action :check_tutorial, except: %i[ index ]

  # GET /home or /homes.json
  def index
  end

  def login
  end


  private
end
