class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book, only: %i[ show edit update confirm_delete destroy ]
  before_action :validate_selected_characters, only: %i[ new create update ]
  before_action :set_ready_character_ids, only: %i[ new create ]
  before_action :enforce_new_book_access, only: :new

  # GET /books or /books.json
  def index
    pending_request_book_ids = current_user.parental_generation_requests.pending.where(kind: "book")
      .select(:generatable_id)
    pending_book_ids = current_user.books.active.where(id: pending_request_book_ids).select(:id)
    @awaiting_books_count = pending_book_ids.count
    all_books = current_user.books.active.where.not(id: pending_book_ids).order(:id).to_a
    @categories = all_books.flat_map(&:categories).uniq.sort
    @selected_category = params[:category].presence_in(@categories)
    @books = if @selected_category
      all_books.select { |book| book.categories.include?(@selected_category) }
    else
      all_books
    end
    @gifted_books = current_user.received_book_gifts.where.not(claimed_at: nil).order(claimed_at: :desc)
    @book = Book.new if all_books.none?
    @tutorial = "new_book_tutorial" if all_books.none?
  end

  def awaiting_approval
    @books = current_user.books.active.joins(:parental_generation_requests)
      .merge(ParentalGenerationRequest.pending).distinct.order(:id)
  end

  # GET /books/1 or /books/1.json
  def show
    @characters = Character.active.where(user: current_user)
    @tutorial = "character_overview_tutorial" unless current_user.characters.active.any?
  end

  # GET /books/new
  def new
    characters = current_user.characters.active.where(id: params[:character_ids])
    @book = Book.new(characters: characters, user: current_user,
      language: current_user.language, reader_age: current_user.reader_age)
    @tutorial = "name_book_tutorial" unless current_user.books.any?
  end

  # GET /books/1/edit
  def edit
    @tutorial = "book_plot_tutorial" unless current_user.books.any? { |book|book.plot.present? }
  end

  # POST /books or /books.json
  def create
    @book = current_user.books.build(book_params)
    @book.total_pages = [ @book.total_pages, @book.tier_limit ].min if @book.tier_limit

    respond_to do |format|
      if save_with_generation_funding
        if @parental_decision.pending?
          notice = I18n.t("notices.parental_generation.book_pending")
        else
          queued = @book.enqueue_generation!(reservation: @generation_reservation,
            release_on_failure: @generation_reservation_newly_acquired)
          notice = queued ? I18n.t("notices.book.created") : @book.generation_failure["message"]
        end
        destination = @parental_decision.pending? ? book_parent_approval_url(@book) : book_url(@book, format: :html)
        format.html { redirect_to destination, notice: notice }
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
        queued = unless @parental_decision.pending?
          @book.enqueue_generation!(reservation: @generation_reservation,
            release_on_failure: @generation_reservation_newly_acquired)
        end
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "book_#{@book.id}",
            partial: "books/book_editor",
            locals: { book: @book })}
        format.html do
          notice = if @parental_decision.pending?
            I18n.t("notices.parental_generation.book_pending")
          elsif queued
            I18n.t("notices.book.writing")
          else
            @book.generation_failure["message"]
          end
          destination = @parental_decision.pending? ? book_parent_approval_url(@book) : book_url(@book)
          redirect_to destination, notice: notice
        end
      else
        status = @funding_required ? :payment_required : :unprocessable_entity
        format.html { render :edit, status: status }
        format.json { render json: book_error_payload, status: status }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def confirm_delete
    render partial: "delete_confirmation_modal", locals: { book: @book }
  end

  def destroy
    @book.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@book),
          turbo_stream.update("modal", "")
        ]
      end
      format.html { redirect_to books_url, notice: I18n.t("notices.book.destroyed") }
      format.json { head :no_content }
    end
  end

  private
    def set_ready_character_ids
      ready_characters = current_user.characters.active.select(&:image_ready_for_book?)
      @ready_character_ids = ready_characters.map { |character| character.id.to_s }
      @ready_character_names = ready_characters.to_h { |character| [ character.id.to_s, character.name ] }
    end

    def validate_selected_characters
      ids = params[:character_ids] || params.dig(:book, :character_ids)
      selected = if ids
        normalized = Array(ids).reject(&:blank?).map(&:to_s).uniq
        records = current_user.characters.active.where(id: normalized).to_a
        return render plain: I18n.t("notices.characters.own_ready_only"), status: :unprocessable_content if records.size != normalized.size
        records
      else
        @book ? @book.characters : []
      end
      unless selected.all?(&:image_ready_for_book?)
        render plain: I18n.t("notices.characters.not_ready"), status: :unprocessable_content
      end
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_book
      @book = current_user.books.active.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def book_params
      params.require(:book).permit(:name, :plot, :total_pages, :language, :reader_age, :art_style, :book_font,
        character_ids: [])
    end

    def save_with_generation_funding
      new_book = @book.new_record?
      Book.transaction do
        @book.save!
        @parental_decision = ParentalGenerationGate.authorize(@book)
        raise ParentalGenerationGate::LimitReached if @parental_decision.limit_reached?
        ensure_new_book_allowance! if new_book && @parental_decision.pending?
        unless @parental_decision.pending?
          @generation_reservation = @book.reserve_generation_funding!
          @generation_reservation_newly_acquired = @generation_reservation&.previously_new_record? || false
        end
      end
      true
    rescue TrialBookReservation::LimitReached
      @book.errors.add(:base, I18n.t("notices.book.trial_limit_create"))
      false
    rescue TrialBookReservation::TrialExpired
      @book.errors.add(:base, I18n.t("notices.book.trial_expired_create"))
      false
    rescue BookCredit::LimitReached
      @funding_required = true
      @book.errors.add(:base, I18n.t("notices.book.credit_required"))
      false
    rescue ActiveRecord::RecordInvalid
      false
    rescue ParentalGenerationGate::LimitReached
      @book.errors.add(:base, I18n.t("notices.parental_generation.daily_limit"))
      false
    end

    def ensure_new_book_allowance!
      return if current_user.book_generation_available?
      raise TrialBookReservation::TrialExpired if current_user.trial_expired?
      raise TrialBookReservation::LimitReached if current_user.trial?

      raise BookCredit::LimitReached
    end

    def update_with_generation_funding
      Book.transaction do
        @book.update!(book_params)
        @parental_decision = ParentalGenerationGate.authorize(@book)
        raise ParentalGenerationGate::LimitReached if @parental_decision.limit_reached?
        unless @parental_decision.pending?
          @generation_reservation = @book.reserve_generation_funding!
          @generation_reservation_newly_acquired = @generation_reservation&.previously_new_record? || false
        end
      end
      true
    rescue TrialBookReservation::LimitReached
      @book.errors.add(:base, I18n.t("notices.book.trial_limit_continue"))
      false
    rescue TrialBookReservation::TrialExpired
      @book.errors.add(:base, I18n.t("notices.trial_ended"))
      false
    rescue BookCredit::LimitReached
      @funding_required = true
      @book.errors.add(:base, I18n.t("notices.book.credit_required"))
      false
    rescue ActiveRecord::RecordInvalid
      false
    rescue ParentalGenerationGate::LimitReached
      @book.errors.add(:base, I18n.t("notices.parental_generation.daily_limit"))
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
