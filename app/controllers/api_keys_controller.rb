class ApiKeysController < ApplicationController
  def create
    key = ApiKey.issue!(organization: current_organization, name: params[:name].presence || "Key #{Time.current.to_i}")

    # Shown once, then never again: only the digest is stored.
    flash[:issued_token] = key.token
    redirect_to settings_path, notice: "API key created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    key = current_organization.api_keys.find(params[:id])
    key.revoke!
    redirect_to settings_path, notice: "API key revoked."
  end
end
