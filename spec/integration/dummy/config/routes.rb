Dummy::Application.routes.draw do
  resources :users, only: [:show, :create]
end
