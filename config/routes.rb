Spree::Core::Engine.add_routes do
  namespace :admin do
    
    # ... existing shipments/stock_locations routes ...
    resources :shipments do
      member do
        post :delhivery_manifest, to: 'delhivery#create_manifest'
        post :delhivery_cancel, to: 'delhivery#delhivery_cancel'
        post :delhivery_track,    to: 'delhivery#sync_tracking'
        get :delhivery_label, to: 'delhivery#download_label'
      end
    end
    
    resources :stock_locations do
      member do
        post :delhivery_pickup, to: 'stock_locations#delhivery_pickup'
      end
    end

    # FIX: Correctly nested Returns Route
    # We target the Spree::ReturnAuthorization model
    resources :return_authorizations, only: [] do
      member do
        post :delhivery_create_pickup, to: 'delhivery_returns#create_pickup'
      end
    end
    
  end

  namespace :api, defaults: { format: 'json' } do
    namespace :v2 do
      namespace :storefront do
        get 'delhivery/check', to: 'delhivery#check'
      end
    end
  end
end