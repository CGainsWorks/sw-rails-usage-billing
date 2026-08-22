class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  layout "signed_out"

  def new
    redirect_to root_path if signed_in?
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      destination = session[:return_to]
      sign_in(user)
      redirect_to destination || root_path, notice: "Signed in as #{user.name}."
    else
      flash.now[:alert] = "That email and password do not match."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    sign_out
    redirect_to new_session_path, notice: "Signed out."
  end
end
