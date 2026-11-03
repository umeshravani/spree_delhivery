# frozen_string_literal: true

Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v3 do
      namespace :store do
        get 'delhivery/serviceability', to: 'delhivery#serviceability'
        get 'delhivery/check', to: 'delhivery#serviceability'
      end

      namespace :admin do
        get 'delhivery/metadata', to: 'delhivery#metadata'
        post 'delhivery/ensure_profiles', to: 'delhivery#ensure_profiles'
      end
    end
  end
end
