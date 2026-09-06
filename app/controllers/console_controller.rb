class ConsoleController < ApplicationController
  skip_before_action :check_tutorial

  def show
    if current_user&.admin?
      render layout: false
    else
      head :forbidden
    end
  end
end
