module Spree
    module Integrations
      class Delhivery < Spree::Integration
        # Configuration Fields
        preference :api_token, :password
        preference :client_name, :string # "REGULAR" or specific client name
        preference :pickup_location_name, :string # Must match Delhivery Dashboard Warehouse Name EXACTLY
        preference :production_mode, :boolean, default: false
        preference :shipping_mode, :string, default: 'Surface' # Options: Surface, Express
        preference :cod_surcharge_amount, :decimal, default: 0.0

        # --- NEW UNIT PREFERENCES ---
        preference :store_weight_unit, :string, default: 'kg' # Options: kg, lbs, oz, g
        preference :store_dimension_unit, :string, default: 'cm' # Options: cm, in, m, mm
        
        validates :preferred_api_token, presence: true
        validates :preferred_pickup_location_name, presence: true
  
        def self.integration_name
          "Delhivery"
        end
        
        # This method is required for the Admin Index page sorting
        def self.integration_group
          "Shipping"
        end
        # --- FIX ENDS HERE ---
  
        def self.icon_path
          "integration_icons/delhivery.png" # Make sure this image exists in your assets folder
        end

        # 4. Helper to get the token (used in your Client)
        def preferred_api_token
        # You can add logic here to decrypt if you want extra security
          preferences[:api_token]
        end
  
        def api_url
          if preferred_production_mode
            "https://track.delhivery.com"
          else
            "https://staging-express.delhivery.com"
          end
        end
      end
    end
  end