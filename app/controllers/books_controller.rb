class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: %i[ show edit update destroy ]
  before_action :validate_selected_characters, only: %i[ new create update ]

  # GET /books or /books.json
  def index
    @books = current_user.books.order(:id)
    @book = Book.new  if current_user.books.none?
    @tutorial = "new_book_tutorial" unless current_user.books.any?
  end

  # GET /books/1 or /books/1.json
  def show
    @characters = Character.where(user: current_user)
    @tutorial = "character_overview_tutorial" unless current_user.characters.any?
  end

  # GET /books/new
  def new
    characters = current_user.characters.where(id: params[:character_ids])
    @book = Book.new(characters: characters, user: current_user)
    @tutorial = "name_book_tutorial" unless current_user.books.any?
  end

  # GET /books/1/edit
  def edit
    @tutorial = "book_plot_tutorial" unless current_user.books.any? { |book|book.plot.present? }
  end

  # POST /books or /books.json
  def create
    @book = current_user.books.build(book_params)
    @book.total_pages = [ @book.total_pages, @book.tier_limit ].min

    respond_to do |format|
      if @book.save
        GenerateBookJob.perform_later(@book.id)
        format.html { redirect_to book_url(@book, format: :html), notice: "Book was successfully created." }
        format.json { render :show, status: :created, location: @book }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    @book.page_count = 5
    respond_to do |format|
      if @book.update(book_params)
        GenerateBookJob.perform_later(@book.id)
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "book_#{@book.id}",
            partial: "books/book_editor",
            locals: { book: @book })}
        format.html { redirect_to book_url(@book), notice: "Book is being written!" }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def destroy
    @book.destroy

    respond_to do |format|
      format.html { redirect_to books_url, notice: "Book was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    def validate_selected_characters
      ids = params[:character_ids] || params.dig(:book, :character_ids)
      selected = if ids
        normalized = Array(ids).reject(&:blank?).map(&:to_s).uniq
        records = current_user.characters.where(id: normalized).to_a
        return render plain: "Choose only your own ready character images.", status: :unprocessable_content if records.size != normalized.size
        records
      else
        @book ? @book.characters : []
      end
      unless selected.all?(&:image_ready_for_book?)
        render plain: "One or more character images are not ready. Choose ready characters or wait for review and generation.", status: :unprocessable_content
      end
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_book
      @book = current_user.books.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def book_params
      params.require(:book).permit(:name, :plot, :total_pages, character_ids: [])
    end
end
