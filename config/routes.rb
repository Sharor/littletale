Rails.application.routes.draw do
  authenticate :user, ->(user) { user.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end
  get "/console", to: "console#show"
  get "pages/:id/illustration_controls", to: "page_illustration_controls#show", as: :illustration_controls_page
  post "pages/:id/regenerate_illustration", to: "page_illustration_controls#regenerate", as: :regenerate_illustration_page
  namespace :admin do
    root to: "dashboard#index"
    resources :page_illustrations, only: [] do
      post :regenerate, on: :member
    end
    resources :character_image_assessments, only: %i[index show] do
      member do
        get :photo
        post :retry_screening
        post :retry_generation
        post :release_character_credit
        post :approve
        post :reject
      end
    end
    resources :failed_books, only: :index
    resources :books, only: [] do
      member do
        post :rerun_generation
        post :release_trial_slot
      end
    end
  end
  get "login", to: "home#login"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resource :settings, only: :show
  resource :profile, only: %i[show update]
  post "settings/book_purchase", to: "purchases#create", as: :settings_book_purchase
  post "settings/subscription", to: "subscriptions#create", as: :settings_subscription
  post "settings/billing_portal", to: "billing_portal#create", as: :settings_billing_portal
  get "settings/checkout/success", to: "purchases#success", as: :settings_checkout_success
  post "webhooks/stripe", to: "stripe_webhooks#create", as: :stripe_webhook
  resources :books do
    resources :book_gifts, only: %i[new create] do
      collection do
        post :prepare
        get :payment_required
      end
    end
  end
  get "gifts/:token", to: "gift_invitations#show", as: :gift_invitation
  post "gifts/:token/claim", to: "gift_invitations#claim", as: :claim_gift_invitation
  post "gifts/:token/switch_account", to: "gift_invitations#switch_account", as: :switch_account_gift_invitation
  resources :received_gifts, only: %i[index show] do
    get "pages/:id/image", to: "received_gift_images#show", as: :page_image
  end
  resources :book_gifts, only: [] do
    post :retry_delivery, on: :member
  end
  resources :characters do
    get :confirm_delete, on: :member
    collection do
      get :select
      post :save_selected
      post :photo_preview
    end
  end

  get "terms", to: "tutorials#terms", as: :terms
  post "terms/accept", to: "tutorials#accept_terms", as: :accept_terms
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
