Rails.application.routes.draw do
  root "dashboard#show"

  resource :session, only: %i[new create destroy]
  resources :customers, only: %i[index show]
  resources :plans, only: %i[index show]
  resources :subscriptions, only: %i[show]
  resources :invoices, only: %i[index show]
  resources :usage_events, only: %i[index], path: "events"
  resource :settings, only: %i[show]
  resources :api_keys, only: %i[create destroy]
  resources :webhook_endpoints, only: %i[create destroy]

  namespace :api do
    namespace :v1 do
      resources :events, only: %i[index create] do
        post :batch, on: :collection
      end
      resources :customers, only: %i[index show create]
      resources :subscriptions, only: %i[index show create] do
        member do
          post :terminate
          get :current_usage
        end
      end
      resources :invoices, only: %i[index show]
      resources :plans, only: %i[index show]
    end
  end

  # Reports the health of the process to a load balancer.
  get "up" => "rails/health#show", as: :rails_health_check

  # A receiver for the app's own webhooks, used by bin/e2e to prove the
  # outbound delivery path really works over HTTP. Never routed in production.
  unless Rails.env.production?
    post "webhook-sink" => "webhook_sink#create", as: :webhook_sink
    get "webhook-sink" => "webhook_sink#index"
  end
end
