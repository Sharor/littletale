class ConsoleController < ApplicationController
  def show
    if current_user.admin?
      render layout: false
    else
      head :forbidden
    end
  end
end
