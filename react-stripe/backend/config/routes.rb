Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get  "health",          to: "payments#health"
      post "payment_intents", to: "payments#create"
      post "webhooks",        to: "payments#webhook"
    end
  end
end
