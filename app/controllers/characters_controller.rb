class CharactersController < ApplicationController
  rescue_from CharacterCredit::LimitReached, with: :character_payment_required

  before_action :authenticate_user!
  before_action :set_character, only: %i[ show edit update destroy ]
  before_action :set_book, only: %i[ new create show edit update select save_selected ]
  before_action :enforce_character_navigation, only: :index
  before_action :enforce_character_generation_access, only: %i[ new create ]

  skip_before_action :check_tutorial, only: [ :confirm_delete ]
  # GET /characters or /characters.json
  def index
    @characters = current_user.characters
  end

  # GET /characters/1 or /characters/1.json
  def show
  end

  # GET /characters/new
  def new
    @character = Character.new(roles: [])
    @tutorial = "new_character_tutorial" unless current_user.characters.any?
  end

  # GET /characters/1/edit
  def edit
    respond_to do |format|
      format.turbo_stream { redirect_to edit_character_url(@character, format: :html), status: :see_other }
      format.html
    end
  end

  # GET /characters/select
  def select
    @characters = Character.where(user: current_user)
    @tutorial = "select_character_tutorial" unless current_user.tutorial&.tutorial_complete

    render "select",  layout: false, locals: { book: @book, characters: @characters }
  end

  # POST /characters/save_selected
  def save_selected
    character_ids = params[:character_ids] || []
    characters = Character.where(id: character_ids, user: current_user)
    unless characters.size == Array(character_ids).reject(&:blank?).map(&:to_s).uniq.size && characters.all?(&:image_ready_for_book?)
      return render plain: I18n.t("notices.characters.own_ready_only"), status: :unprocessable_content
    end
    current_user.tutorial.update(tutorial_complete: true)

    @book.character_ids = characters.map(&:id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "book_characters",
            partial: "books/characters",
            locals: { book: @book }
          ),
          turbo_stream.replace(
            "character_select_modal",
            helpers.turbo_frame_tag("character_select_modal")) ]
      end
      format.html { redirect_to @book, notice: I18n.t("notices.characters.added", count: characters.count) }
    end
  end

  # POST /characters/photo_preview
  def photo_preview
    blob = ActiveStorage::Blob.create_and_upload!(
    io: params[:photo].tempfile,
    filename: params[:photo].original_filename,
    content_type: params[:photo].content_type)

    respond_to do |format|
      format.html { render partial: "characters/photo_preview", locals: { blob: blob } }
    end
  end

  # POST /characters or /characters.json
  def create
      char_id_from_frontend = params[:character].keys.first
      permitted_params = character_params
      photo_file = permitted_params.delete(:photo_upload)
      @character = Character.new(permitted_params)
      @character.user = current_user
      # @character.book = @book if @book

      @character.photo.attach(photo_file) if photo_file.present? && @character.creation_mode != "form"

      respond_to do |format|
          if @character.save
              # 1. Kick off the asynchronous job, passing the frontend ID for the later broadcast
              @character.setup_illustration(char_id_from_frontend)
              target_id = "character-#{char_id_from_frontend}"
              format.html { redirect_to characters_url, notice: I18n.t("illustrations.checking") }
          else
              # 3. Handle validation errors
              target_id = "character-#{char_id_from_frontend}"
              format.html { render :new, status: :unprocessable_content }
          end
      end
  end

  # PATCH/PUT /characters/1 or /characters/1.json
  def update
    respond_to do |format|
      attributes = character_params
      photo_file = attributes.delete(:photo_upload)
      @character.assign_attributes(attributes)
      @character.photo = nil if @character.creation_mode == "form"
      @character.photo.attach(photo_file) if photo_file.present? && @character.creation_mode != "form"
      if character_generation_credit_required?
        @character.errors.add(:base, I18n.t("notices.characters.credit_required"))
        format.html { render_payment_required("character", redirect_status: :see_other) }
        format.json do
          render json: { error: "character_credit_required", settings_url: settings_url,
            errors: @character.errors.to_hash }, status: :payment_required
        end
      elsif @character.save
        @character.setup_illustration
        format.turbo_stream { redirect_to(@book ? book_url(@book) : characters_url, status: :see_other) }
        format.html { redirect_to(@book ? book_url(@book) : characters_url, notice: I18n.t("notices.characters.updated")) }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @character.errors, status: :unprocessable_entity }
      end
    end
  end

  # Necessary because of label logic in view
  def confirm_delete
    @character = current_user.characters.find(params[:id])

    # CRITICAL: Explicitly render the partial. Do NOT implicitly render a view or redirect.
    render partial: "delete_confirmation_modal", locals: { character: @character }
  end

  # DELETE /characters/1 or /characters/1.json
  def destroy
    @character = current_user.characters.find(params[:id])
    @character.destroy

    # Respond with Turbo Stream
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # 1. Remove the character card from the DOM
          turbo_stream.remove(@character),
          # 2. Clear the content of the modal frame
          turbo_stream.replace("modal", '<turbo-frame id="modal"></turbo-frame>')
        ]
      end
      format.html { redirect_to characters_url, notice: I18n.t("notices.characters.destroyed") }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_character
      @character = current_user.characters.find(params[:id])
    end

    def set_book
      param = params[:book_id] || params.dig(:character, :book_id)
      @book = current_user.books.find(param) if param.present?
      @path = params[:path]
    end

    # Only allow a list of trusted parameters through.
    def character_params
      params.require(:character).permit(:photo, :name, :age, :hair_color, :gender,
          :hair_style, :eye_color, :ethnicity, :photo_upload, :creation_mode, roles: [])
    end

    def enforce_character_navigation
      has_books = current_user.book_generation_available?
      has_characters = current_user.character_generation_available?
      if !has_books && !has_characters
        render_payment_required("both")
      elsif !has_books && params[:continue] != "1"
        @show_book_credit_advisory = true
      end
    end

    def enforce_character_generation_access
      return if current_user.character_generation_available?

      render_payment_required("character")
    end

    def character_payment_required
      render_payment_required("character", redirect_status: :see_other)
    end

    def character_generation_credit_required?
      return false if current_user.character_generation_available?

      image_request = @character.current_image_request
      return true unless image_request && CharacterFunding.funded?(image_request)

      CharacterImageRequest.snapshot_for(@character).fetch(:fingerprint) != image_request.assessment.fingerprint
    end

    def render_payment_required(reason, redirect_status: :found)
      if request.format.json?
        render json: { error: "#{reason}_credit_required", settings_url: settings_url }, status: :payment_required
      else
        redirect_to settings_path(payment_required: reason), status: redirect_status
      end
    end
end
