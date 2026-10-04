# frozen_string_literal: true

class Parent::ControlsController < Parent::BaseController
  def update
    parent_control.assign_attributes(control_params)
    if parent_control.mode == "daily_limit" && !parent_control.subscription_features_available?
      parent_control.errors.add(:base, I18n.t("parent.control.subscription_required"))
    end

    if parent_control.errors.empty? && parent_control.save
      redirect_to parent_url, notice: I18n.t("parent.control.updated")
    else
      load_dashboard
      render "parent/dashboard/show", status: :unprocessable_content
    end
  end

  private

  def control_params
    params.require(:parent_control).permit(:mode, :daily_book_limit, :time_zone)
  end
end
