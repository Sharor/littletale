class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: %i[ show edit update destroy ]
  before_action :validate_selected_characters, only: %i[ new create update ]
  before_action :enforce_new_book_access, only: :new

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
      if save_with_generation_funding
        queued = @book.enqueue_generation!(reservation: @generation_reservation,
          release_on_failure: @generation_reservation_newly_acquired)
        notice = queued ? "Book was successfully created." : @book.generation_failure["message"]
        format.html { redirect_to book_url(@book, format: :html), notice: notice }
        format.json { render :show, status: :created, location: @book }
      else
        status = @funding_required ? :payment_required : :unprocessable_content
        format.html { render :new, status: status }
        format.json { render json: book_error_payload, status: status }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    @book.page_count = 5
    respond_to do |format|
      if update_with_generation_funding
        queued = @book.enqueue_generation!(reservation: @generation_reservation,
          release_on_failure: @generation_reservation_newly_acquired)
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "book_#{@book.id}",
            partial: "books/book_editor",
            locals: { book: @book })}
        format.html do
          notice = queued ? "Book is being written!" : @book.generation_failure["message"]
          redirect_to book_url(@book), notice: notice
        end
      else
        status = @funding_required ? :payment_required : :unprocessable_entity
        format.html { render :edit, status: status }
        format.json { render json: book_error_payload, status: status }
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

    def save_with_generation_funding
      Book.transaction do
        @book.save!
        @generation_reservation = @book.reserve_generation_funding!
        @generation_reservation_newly_acquired = @generation_reservation&.previously_new_record? || false
      end
      true
    rescue TrialBookReservation::LimitReached
      @book.errors.add(:base, "The trial includes three trial books. Subscribe to create another book.")
      false
    rescue TrialBookReservation::TrialExpired
      @book.errors.add(:base, "The trial has expired. Subscribe to create another book.")
      false
    rescue BookCredit::LimitReached
      @funding_required = true
      @book.errors.add(:base, "You need a book credit to generate another book.")
      false
    rescue ActiveRecord::RecordInvalid
      false
    end

    def update_with_generation_funding
      Book.transaction do
        @book.update!(book_params)
        @generation_reservation = @book.reserve_generation_funding!
        @generation_reservation_newly_acquired = @generation_reservation&.previously_new_record? || false
      end
      true
    rescue TrialBookReservation::LimitReached
      @book.errors.add(:base, "The trial includes three trial books. Subscribe to continue.")
      false
    rescue TrialBookReservation::TrialExpired
      @book.errors.add(:base, "The trial has expired. Subscribe to continue.")
      false
    rescue BookCredit::LimitReached
      @funding_required = true
      @book.errors.add(:base, "You need a book credit to generate another book.")
      false
    rescue ActiveRecord::RecordInvalid
      false
    end

    def enforce_new_book_access
      return if current_user.book_generation_available?

      if request.format.json?
        render json: { error: "book_credit_required", settings_url: settings_url }, status: :payment_required
      else
        redirect_to settings_path(payment_required: "book")
      end
    end

    def book_error_payload
      return @book.errors unless @funding_required

      { error: "book_credit_required", settings_url: settings_url, errors: @book.errors.to_hash }
    end
end
