Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [:index, :show, :create, :update, :destroy]
    end
  end

  resource :checkout, only: [:new, :create], controller: 'checkout' do
    get 'payment', on: :collection
    post 'confirm', on: :collection
    get 'complete', on: :collection
  end
end
