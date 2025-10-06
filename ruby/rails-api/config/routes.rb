Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :show, :create, :update, :destroy]
      
      # Routes for our new user_info controller
      # These map URLs to controller actions
      get 'user_info', to: 'user_info#index'           # GET /api/v1/user_info
      post 'user_info/create', to: 'user_info#create'  # POST /api/v1/user_info/create
      get 'user_info/validate', to: 'user_info#validate' # GET /api/v1/user_info/validate?email=test@example.com
    end
  end

  resource :checkout, only: [:new, :create], controller: 'checkout' do
    get 'payment', on: :collection
    post 'confirm', on: :collection
    get 'complete', on: :collection
  end
end
