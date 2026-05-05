module Spree
  module Api
    module V3
      module Store
        class DelhiveryController < ::Spree::Api::V3::BaseController
          # V3 best practice: skip size checks for simple GET/POST validation requests
          skip_before_action :ensure_payload_size, raise: false
          skip_before_action :check_payload_size, raise: false

          def check
            pincode = params[:pincode]
            mode = params[:mode] || 'Surface'
            
            cutoff_h = (params[:cutoff_hour] || '14').to_i
            cutoff_m = params[:cutoff_meridiem] || 'PM'

            return render json: { error: "Invalid Pincode" }, status: 400 if pincode.blank? || pincode.length != 6

            # Determine Source Pin using Spree 5.4 methods
            stock_location = Spree::StockLocation.where(active: true).where.not(zipcode: nil).first
            source_pin = stock_location&.zipcode || "110001" 

            client = SpreeDelhivery::Client.new
            
            # --- 1. IMPROVED LOCATION LOGIC (City + District + State) ---
            location_text = "Valid Location"
            begin
              details = client.fetch_pincode_details(pincode)
              if details
                d = details.with_indifferent_access
                
                # Clean City (Remove S.O/B.O suffixes)
                raw_city = d[:city].presence || ""
                city_name = raw_city.to_s.gsub(/\s+(S\.?O|B\.?O|H\.?O)\.?$/i, '').strip.titleize

                # Clean District
                raw_dist = d[:district].presence || ""
                dist_name = raw_dist.to_s.gsub(/\s+District$/i, '').strip.titleize

                # Parse State
                raw_state = (d[:state] || d[:state_code] || d[:province]).to_s.strip
                state_name = raw_state.titleize

                # India State Map Correction
                state_map = {
                  'TS' => 'Telangana', 'TG' => 'Telangana', 'DL' => 'Delhi',
                  'MH' => 'Maharashtra', 'KA' => 'Karnataka', 'TN' => 'Tamil Nadu',
                  'UP' => 'Uttar Pradesh', 'WB' => 'West Bengal', 'AP' => 'Andhra Pradesh',
                  'GJ' => 'Gujarat', 'RJ' => 'Rajasthan', 'KL' => 'Kerala', 'HR' => 'Haryana',
                  'PB' => 'Punjab', 'MP' => 'Madhya Pradesh', 'BR' => 'Bihar',
                  'CG' => 'Chhattisgarh', 'JH' => 'Jharkhand', 'UK' => 'Uttarakhand', 
                  'HP' => 'Himachal Pradesh', 'AS' => 'Assam', 'OR' => 'Odisha'
                }

                # Resolve Official State Name via Spree DB
                india = Spree::Country.find_by(iso: 'IN')
                if india
                  state_match = india.states.where("LOWER(abbr) = ? OR LOWER(name) = ?", raw_state.downcase, raw_state.downcase).first
                  if state_match
                    state_name = state_match.name 
                  elsif state_map[raw_state.upcase]
                    state_name = state_map[raw_state.upcase]
                  end
                end

                # Build Full Location String
                parts = []
                parts << city_name if city_name.present?
                parts << dist_name if dist_name.present? && dist_name.downcase != city_name.downcase
                if state_name.present? && state_name.downcase != city_name.downcase && state_name.downcase != dist_name.downcase
                  parts << state_name
                end

                location_text = parts.join(', ') if parts.any?
              end
            rescue => e
              Rails.logger.error "Delhivery City Parse Error: #{e.message}"
            end

            # --- 2. TAT & Timer Logic ---
            response = client.calculate_tat(source_pin: source_pin, dest_pin: pincode, mode: mode)

            if response && (response['success'] == true || response['estimated_delivery_date'])
              if response['data'] && response['data']['tat']
                 delivery_date = Date.today + response['data']['tat'].to_i.days
              elsif response['estimated_delivery_date']
                 delivery_date = Date.parse(response['estimated_delivery_date'])
              else
                 delivery_date = Date.today + 5.days
              end
              
              date_text = "Delivery by #{delivery_date.strftime("%A, %B %d")}"
              
              # Timer Calculation
              cutoff_24 = cutoff_h
              if cutoff_m.upcase == 'PM' && cutoff_h < 12
                cutoff_24 += 12
              elsif cutoff_m.upcase == 'AM' && cutoff_h == 12
                cutoff_24 = 0
              end

              now = Time.current
              target_time = now.change(hour: cutoff_24, min: 0, sec: 0)
              target_time += 1.day if now > target_time
              
              remaining = (target_time - now).to_i
              timer_text = "#{remaining / 3600} hrs #{(remaining % 3600) / 60} mins"

              # V3 Standard: Wrap response in a 'data' block
              render json: { 
                success: true, 
                data: {
                  date_text: date_text,
                  location_text: location_text, 
                  timer_text: timer_text
                }
              }
            else
              render json: { success: false, error: "Delivery not available." }
            end
          end
        end
      end
    end
  end
end
