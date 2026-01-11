Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :show, :create, :update, :destroy]

      # Payment namespace
      scope :payment do
        get 'status', to: 'payment#status'
        post 'process', to: 'payment#process_payment'
        post 'refund', to: 'payment#refund'
        get 'transactions', to: 'payment#transactions'
      end

      # Auth namespace
      scope :auth do
        post 'login', to: 'auth#login'
        post 'logout', to: 'auth#logout'
        post 'refresh', to: 'auth#refresh'
        get 'verify', to: 'auth#verify'
        post 'register', to: 'auth#register'
      end

      # Internal namespace
      scope :internal do
        get 'health', to: 'internal#health'
        get 'metrics', to: 'internal#metrics'
        post 'sync', to: 'internal#sync'
        post 'cache/invalidate', to: 'internal#cache_invalidate'
        get 'config', to: 'internal#get_config'
        post 'jobs/trigger', to: 'internal#trigger_job'
      end

      # Public endpoints - NO service.namespace attribute
      scope :public do
        get 'ping', to: 'public#ping'
        get 'version', to: 'public#version'
        get 'echo', to: 'public#echo'
      end
    end
  end

  resource :checkout, only: [:new, :create], controller: 'checkout' do
    get 'payment', on: :collection
    post 'confirm', on: :collection
    get 'complete', on: :collection
  end
end
