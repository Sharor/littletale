# frozen_string_literal: true

class PrintOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_lulu_orders_access!

  def index
    @orders = []
  end

  private

  def require_lulu_orders_access!
    head :not_found unless Lulu::Configuration.enabled? && current_user.admin?
  end
end
