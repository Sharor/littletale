class Admin::CharactersController < ApplicationController
  skip_before_action :check_tutorial
  before_action :require_admin

  def index
    @characters = Character.deleted.includes(:user).order(deleted_at: :desc)
  end

  def restore
    Character.deleted.find(params[:id]).update!(deleted_at: nil)
    redirect_to admin_characters_path, notice: I18n.t("admin.characters.restored"), status: :see_other
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
