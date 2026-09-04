Rails.application.routes.draw do
  authenticate :user, ->(user) { user.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end
  get "/console", to: "console#show"
  get "login", to: "home#login"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :books
  resources :chatgpts
  resources :characters do
    get :confirm_delete, on: :member
    collection do
      get :select
      post :save_selected
      post :photo_preview
    end
  end
  resources :illustrations
  resources :pages

  get "terms", to: "tutorials#terms", as: :terms
  get "eula", to: "tutorials#eula", as: :eula
  get "tutorial", to: "tutorials#tutorial", as: :tutorial
  post "complete", to: "tutorials#complete", as: :tutorial_complete


  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks",  sessions: "sessions" }
  devise_scope :user do
    get "sign_in", to: "sessions#new", as: :new_user_session
    delete "sign_out", to: "devise/sessions#destroy", as: :destroy_user_session
  end


  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  authenticated :user do
    root "books#index", as: :authenticated_root
  end

  unauthenticated do
    root "home#index", as: :unauthenticated_root
  end
end
