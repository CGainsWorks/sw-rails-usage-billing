class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting and CSS :has.
  allow_browser versions: :modern

  before_action :require_authentication

  helper_method :current_user, :current_organization, :signed_in?

  class << self
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def current_user
    Current.user ||= User.find_by(id: session[:user_id])
  end

  def current_organization
    Current.organization ||= current_user&.organization
  end

  def signed_in? = current_user.present?

  def require_authentication
    return if signed_in?

    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to new_session_path, alert: "Sign in to continue."
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    Current.user = user
  end

  def sign_out
    reset_session
    Current.user = nil
    Current.organization = nil
  end
end
