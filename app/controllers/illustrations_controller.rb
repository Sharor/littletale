class IllustrationsController < ApplicationController
  before_action :set_illustration, only: %i[ show edit update destroy ]

  # GET /illustrations or /illustrations.json
  def index
    @illustrations = Illustration.all
  end

  # GET /illustrations/1 or /illustrations/1.json
  def show
  end

  # GET /illustrations/new
  def new
    @illustration = Illustration.new
  end

  # GET /illustrations/1/edit
  def edit
  end

  # POST /illustrations or /illustrations.json
  def create
    @illustration = Illustration.new(illustration_params)

    respond_to do |format|
      if @illustration.save
        format.html { redirect_to @illustration, notice: "Illustration was successfully created." }
        format.json { render :show, status: :created, location: @illustration }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @illustration.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /illustrations/1 or /illustrations/1.json
  def update
    respond_to do |format|
      if @illustration.update(illustration_params)
        format.html { redirect_to @illustration, notice: "Illustration was successfully updated." }
        format.json { render :show, status: :ok, location: @illustration }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @illustration.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /illustrations/1 or /illustrations/1.json
  def destroy
    @illustration.destroy!

    respond_to do |format|
      format.html { redirect_to illustrations_path, status: :see_other, notice: "Illustration was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_illustration
      @illustration = Illustration.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def illustration_params
      params.expect(illustration: [ :prompt, :image_url, :original_image, :page_id ])
    end
end
