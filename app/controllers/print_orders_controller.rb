# frozen_string_literal: true

class PrintOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_lulu_orders_access!
  before_action :set_order, only: %i[show address update_address options read]

  def index
    @orders = current_user.print_orders.order(created_at: :desc)
  end

  def new
    load_eligible_books
  end

  def create
    book = current_user.books.find(params[:book_id])
    order = PrintOrder.start_for!(user: current_user, book:)
    redirect_to print_order_path(order)
  rescue PrintOrder::IneligibleBook
    load_eligible_books
    @book_error = I18n.t("print_orders.errors.ineligible_book")
    render :new, status: :unprocessable_content
  end

  def show
  end

  def address
    @order.update_column(:step, 2) if @order.step < 2
  end

  def update_address
    if @order.save_delivery_address(address_params)
      redirect_to options_print_order_path(@order)
    else
      render :address, status: :unprocessable_content
    end
  end

  def options
    unless @order.address_complete?
      redirect_to address_print_order_path(@order), alert: I18n.t("print_orders.errors.complete_address")
    end
  end

  def read
    @reader_back_path = if @order.step >= 3
      options_print_order_path(@order)
    elsif @order.step == 2
      address_print_order_path(@order)
    else
      print_order_path(@order)
    end
  end

  private

  def require_lulu_orders_access!
    head :not_found unless Lulu::Configuration.enabled? && current_user.admin?
  end

  def set_order
    @order = current_user.print_orders.find(params[:id])
  end

  def load_eligible_books
    @books = current_user.books.completed.order(updated_at: :desc).select do |book|
      PrintOrder.eligible_book?(user: current_user, book:)
    end
  end

  def address_params
    params.require(:print_order).permit(
      :recipient_name, :street1, :street2, :city, :postcode, :country_code,
      :state_code, :recipient_email, :phone_number
    )
  end
end
