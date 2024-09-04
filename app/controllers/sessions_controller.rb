class SessionsController < ApplicationController
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
      session = user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.ip
      )
      redirect_to user_path(user), notice: "You have been signed in."
    else
      redirect_to new_session_path(screen_name_hint: session_params.dig(:user, :screen_name)), alert: "Try another email address or password."
    end
  end

  private
    # Only allow a list of trusted parameters through.
    def session_params
      params.require(:session).permit(user: [ :screen_name, :password ])
    end
end
