Rails.application.routes.draw do
  resources :todo_lists, only: [:index, :show, :create, :destroy] do
    post 'bulk_create', on: :collection
    patch 'update', on: :collection
  end
end
