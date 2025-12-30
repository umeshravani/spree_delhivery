module Spree
  module Calculator::Shipping
    class Delhivery < Spree::ShippingCalculator
      
      preference :handling_fee, :decimal, default: 0.0
      preference :service_mode, :string, default: 'Surface' # Full Name

      def self.description
        "Delhivery Live Rate"
      end

      def compute_package(package)
        integration = Spree::Integrations::Delhivery.active.first
        return nil unless integration

        order = package.order
        stock_location = package.stock_location
        return nil unless stock_location&.zipcode && order.ship_address&.zipcode

        origin_pin = stock_location.zipcode
        dest_pin = order.ship_address.zipcode

        store_weight_unit = integration.preferred_store_weight_unit.to_s.downcase
        store_dim_unit    = integration.preferred_store_dimension_unit.to_s.downcase

        total_actual_weight_gms = 0.0
        total_volumetric_weight_gms = 0.0

        package.contents.each do |item|
          variant = item.variant
          qty = item.quantity

          # Weight to Grams
          w_raw = variant.weight.to_f
          w_gms = case store_weight_unit
                  when 'kg', 'kilograms' then w_raw * 1000.0
                  when 'lbs', 'pounds'   then w_raw * 453.592
                  when 'oz', 'ounces'    then w_raw * 28.3495
                  when 'g', 'grams'      then w_raw
                  else w_raw * 1000.0
                  end
          
          total_actual_weight_gms += (w_gms * qty)

          # Dimensions to CM
          l_raw = variant.depth.to_f
          w_raw = variant.width.to_f
          h_raw = variant.height.to_f

          if l_raw.zero?
             l_raw = (store_dim_unit == 'mm' ? 100.0 : 10.0)
             w_raw = (store_dim_unit == 'mm' ? 100.0 : 10.0)
             h_raw = (store_dim_unit == 'mm' ? 10.0 : 1.0)
          end

          to_cm = ->(val) {
            case store_dim_unit
            when 'mm', 'millimeters' then val / 10.0
            when 'm', 'meters'       then val * 100.0
            when 'in', 'inches'      then val * 2.54
            when 'cm', 'centimeters' then val
            else val
            end
          }

          vol_weight_kg = (to_cm.call(l_raw) * to_cm.call(w_raw) * to_cm.call(h_raw)) / 5000.0
          total_volumetric_weight_gms += (vol_weight_kg * 1000.0 * qty)
        end

        chargeable_weight_gms = [total_actual_weight_gms, total_volumetric_weight_gms].max.to_i
        chargeable_weight_gms = 50 if chargeable_weight_gms < 50
        
        client = SpreeDelhivery::Client.new
        
        begin
          # Mode 'Surface'/'Express' passed directly
          mode = preferred_service_mode 
          cache_key = "delhivery_rate_#{origin_pin}_#{dest_pin}_#{chargeable_weight_gms}_#{mode}"
          
          rate = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
            client.fetch_shipping_rate(
              source_pin: origin_pin, 
              dest_pin: dest_pin, 
              weight_gms: chargeable_weight_gms,
              mode: mode
            )
          end
          
          rate ? rate + preferred_handling_fee : nil
        rescue StandardError => e
          Rails.logger.error "Delhivery Calculator Error: #{e.message}"
          return nil 
        end
      end
    end
  end
end