class ChatgptsController < ApplicationController
  before_action :set_chatgpt, only: %i[ show edit update destroy ]

  # GET /chatgpts or /chatgpts.json
  def index
    @chatgpts = Chatgpt.all
  end

  # GET /chatgpts/1 or /chatgpts/1.json
  def show
  end

  # GET /chatgpts/new
  def new
    @chatgpt = Chatgpt.new
  end

  # GET /chatgpts/1/edit
  def edit
  end

  # POST /chatgpts or /chatgpts.json
  def create
    @chatgpt = Chatgpt.new(chatgpt_params)

    respond_to do |format|
      if @chatgpt.save
        format.html { redirect_to chatgpt_url(@chatgpt), notice: "Chatgpt was successfully created." }
        format.json { render :show, status: :created, location: @chatgpt }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @chatgpt.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /chatgpts/1 or /chatgpts/1.json
  def update
    respond_to do |format|
      if @chatgpt.update(chatgpt_params)
        format.html { redirect_to chatgpt_url(@chatgpt), notice: "Chatgpt was successfully updated." }
        format.json { render :show, status: :ok, location: @chatgpt }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @chatgpt.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /chatgpts/1 or /chatgpts/1.json
  def destroy
    @chatgpt.destroy

    respond_to do |format|
      format.html { redirect_to chatgpts_url, notice: "Chatgpt was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_chatgpt
      @chatgpt = Chatgpt.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def chatgpt_params
      params.require(:chatgpt).permit(:prompt, :answer, :max_tokens, :reason_for_termination, :usage)
    end
end
