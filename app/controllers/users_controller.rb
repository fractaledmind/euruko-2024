class UsersController < ApplicationController
  # ----- unauthenticated actions -----
  allow_unauthenticated_access only: %i[ show new create ]

  # GET /users/1
  def show
    @user = User.find(params[:id])
  end

  # GET /users/new
  def new
    @user = User.new
  end

  # POST /users
  def create
    @user = User.new(user_params)

    if @user.save
      start_new_session_for @user
      redirect_to @user, notice: "Welcome! You have signed up successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ----- authenticated actions -----
  before_action :set_current_user, only: %i[ edit update destroy ]

  # GET /users/1/edit
  def edit
  end

  # PATCH/PUT /users/1
  def update
    if @user.update(user_params)
      redirect_to @user, notice: "Profile was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /users/1
  def destroy
    @user.destroy!
    redirect_to users_url, notice: "Profile was successfully deleted."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_current_user
      @user = Current.user
    end

    # Only allow a list of trusted parameters through.
    def user_params
      params.require(:user).permit(:screen_name, :password, :password_confirmation, :about)
    end
end
