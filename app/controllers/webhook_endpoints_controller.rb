class WebhookEndpointsController < ApplicationController
  def create
    endpoint = current_organization.webhook_endpoints.new(url: params[:url])

    if endpoint.save
      redirect_to settings_path, notice: "Webhook endpoint added."
    else
      redirect_to settings_path, alert: endpoint.errors.full_messages.to_sentence
    end
  end

  def destroy
    endpoint = current_organization.webhook_endpoints.find(params[:id])
    endpoint.destroy!
    redirect_to settings_path, notice: "Webhook endpoint removed."
  end
end
