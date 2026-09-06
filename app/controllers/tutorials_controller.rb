class TutorialsController < ApplicationController
  before_action :set_tutorial, only: %i[ eula terms tutorial complete ]
  skip_before_action :check_tutorial, only: %i[ eula terms tutorial ]


  def eula
  end

  def terms
    @tutorial.update(eula: true)
  end

  def tutorial
    @tutorial.update(terms: true)
  end

  def complete
    @tutorial.update!(tutorial_complete: true)
    redirect_to authenticated_root_url
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_tutorial
      @tutorial = Tutorial.where(user: current_user).first_or_create(eula: false, terms: false, tutorial_complete: false)
    end

    # Only allow a list of trusted parameters through.
    def tutorial_params
      params.expect(tutorial: [ :eula, :terms, :tutorial_complete, :user_id ])
    end
end
