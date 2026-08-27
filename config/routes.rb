Rails.application.routes.draw do
  root "home#index"
  devise_for :users,
              skip: [ :sessions, :registrations ],
              controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  devise_scope :user do
    get     "login", to: "sessions#new",         as: :new_user_session
    post    "login", to: "sessions#create",      as: :user_session
    delete "logout", to: "sessions#destroy",     as: :destroy_user_session

    get  "register", to: "registrations#new",    as: :new_user_registration
    post "register", to: "registrations#create", as: :user_registration
  end

  resource :profile_completion, only: [ :edit, :update ], controller: "profile_completions"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
