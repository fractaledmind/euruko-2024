class SessionsController < ApplicationController
  # ----- unauthenticated actions -----
  allow_unauthenticated_access only: %i[ new create ]

  # GET /sessions/new
  def new
    @session = Session.new
  end

  # POST /sessions
  def create
    user = User.authenticate_by(
      screen_name: session_params.dig(:user, :screen_name),
      password: session_params.dig(:user, :password)
    )

    if user
      start_new_session_for user
      redirect_to after_authentication_url, notice: "You have been signed in."
    else
      redirect_to new_session_path(screen_name_hint: session_params.dig(:user, :screen_name)), alert: "Try another email address or password."
    end
  end

  # ----- authenticated actions -----
  before_action :set_and_authorize_session, only: %i[ destroy ]

  # DELETE /sessions/1
  def destroy
    @session.destroy!
    redirect_to @session.user, notice: "That session has been successfully logged out."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_and_authorize_session
      @session = Current.user.sessions.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def session_params
      params.require(:session).permit(user: [ :screen_name, :password ])
    end
end
