class SettingsController < ApplicationController
  def show
    @api_keys = current_organization.api_keys.order(created_at: :desc)
    @webhook_endpoints = current_organization.webhook_endpoints.order(created_at: :desc)
    @issued_token = flash[:issued_token]
  end
end
