class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy ]
  before_action :set_book, only: %i[ new create show edit update select save_selected ]

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
      format.turbo_stream do
        locals = { character: @character }
        locals[:book] = @book if @book


        render turbo_stream: turbo_stream.replace(
          "character_modal",
          partial: "characters/modal",
          locals: locals
        )
      end
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
            render_to_string(partial: "characters/empty_character_modal", locals: { hidden: true })) ]
      end
      format.html { redirect_to @book, notice: "#{characters.count} character(s) added to the book!" }
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

      @character.photo.attach(photo_file) if photo_file.present?

      respond_to do |format|
          if @character.save
              # 1. Kick off the asynchronous job, passing the frontend ID for the later broadcast
              @character.setup_illustration(char_id_from_frontend)
              target_id = "character-#{char_id_from_frontend}"
              format.html { redirect_to characters_url, notice: "Making your character.." }
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
      if @character.update(character_params)
        @character.setup_illustration
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("book_characters", partial: "books/characters", locals: { book: @book }),
            turbo_stream.replace("character_modal", partial: "characters/empty_character_modal", locals: { hidden: true }) ] # Hide Modal
        end
        format.html { redirect_to book_url(@book), notice: "Character was successfully updated." }
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
    @character = Character.find(params[:id])
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
      format.html { redirect_to characters_url, notice: "Character was successfully destroyed." }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_character
      @character = current_user.characters.find(params[:id])
    end

    def set_book
      param = params[:book_id] || params.dig(:character, :book_id)
      @book = Book.find(param) if param.present?
      @path = params[:path]
    end

    # Only allow a list of trusted parameters through.
    def character_params
      params.require(:character).permit(:photo, :name, :age, :hair_color, :gender,
          :hair_style, :eye_color, :ethnicity, :photo_upload, :creation_mode, roles: [])
    end
end
