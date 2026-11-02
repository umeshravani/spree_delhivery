# frozen_string_literal: true

require 'faraday'
require 'json'

module Spree
  module Api
    module V3
      module Store
        class DelhiveryController < ::Spree::Api::V3::Store::BaseController
          skip_before_action :ensure_payload_size, raise: false
          skip_before_action :check_payload_size, raise: false

          INDIA_STATE_MAP = {
            'TS' => 'Telangana', 'TG' => 'Telangana', 'DL' => 'Delhi',
            'MH' => 'Maharashtra', 'KA' => 'Karnataka', 'TN' => 'Tamil Nadu',
            'UP' => 'Uttar Pradesh', 'WB' => 'West Bengal', 'AP' => 'Andhra Pradesh',
            'GJ' => 'Gujarat', 'RJ' => 'Rajasthan', 'KL' => 'Kerala', 'HR' => 'Haryana',
            'PB' => 'Punjab', 'MP' => 'Madhya Pradesh', 'BR' => 'Bihar',
            'CG' => 'Chhattisgarh', 'JH' => 'Jharkhand', 'UK' => 'Uttarakhand',
            'HP' => 'Himachal Pradesh', 'AS' => 'Assam', 'OR' => 'Odisha',
            'GA' => 'Goa', 'JK' => 'Jammu and Kashmir', 'CH' => 'Chandigarh'
          }.freeze

          # GET /api/v3/store/delhivery/serviceability?pincode=400001
          # GET /api/v3/store/delhivery/check?pincode=400001
          def serviceability
            raw_pin = params[:pincode].to_s.strip
            clean_pin = raw_pin.gsub(/\D/, '').slice(0, 6)

            if clean_pin.length != 6
              return render json: {
                pincode: raw_pin,
                serviceable: false,
                message: 'Please enter a valid 6-digit Indian PIN code.'
              }, status: :bad_request
            end

            result = query_delhivery_serviceability(clean_pin)
            render json: result
          end

          private

          def query_delhivery_serviceability(pincode)
            api_token, _client_name, test_mode = resolve_delhivery_credentials

            if api_token.blank?
              Rails.logger.warn("[Delhivery] Serviceability check skipped: no API token configured")
              return {
                pincode: pincode,
                serviceable: false,
                message: 'Delivery serviceability check unavailable.'
              }
            end

            base_url = test_mode ? 'https://staging-express.delhivery.com' : 'https://track.delhivery.com'

            # 1. Fetch carrier postal code serviceability
            carrier_resp = fetch_carrier_pin_data(base_url, api_token, pincode)
            return carrier_resp if carrier_resp[:serviceable] == false

            postal_code = carrier_resp[:postal_code]
            is_prepaid = postal_code['pre_paid'].to_s.upcase == 'Y'
            is_cod = postal_code['cod'].to_s.upcase == 'Y' || postal_code['cash'].to_s.upcase == 'Y'
            is_serviceable = is_prepaid || is_cod

            unless is_serviceable
              return {
                pincode: pincode,
                serviceable: false,
                cod_available: false,
                prepaid_available: false,
                message: 'PIN code is currently unserviceable.'
              }
            end

            # 2. Location formatting and normalization
            city_name, dist_name, state_name, state_code = format_location_details(postal_code)
            location_parts = [city_name, (dist_name != city_name ? dist_name : nil), state_name].compact.reject(&:blank?)
            location_text = location_parts.join(', ')

            # 3. Verified ETA (fail-safe without fabricating days)
            tat_days = resolve_verified_tat(base_url, api_token, postal_code, pincode)
            estimated_days = tat_days.present? ? "#{tat_days} business days" : nil

            {
              pincode: pincode,
              serviceable: true,
              city: city_name.presence || dist_name,
              district: dist_name,
              state: state_name,
              state_code: state_code,
              location: location_text,
              cod_available: is_cod,
              prepaid_available: is_prepaid,
              estimated_days: estimated_days,
              message: "Deliverable to #{city_name.presence || dist_name.presence || 'your area'}."
            }
          rescue Faraday::TimeoutError, Timeout::Error => e
            Rails.logger.error("[Delhivery] Timeout querying pincode #{pincode}: #{e.message}")
            {
              pincode: pincode,
              serviceable: false,
              message: 'Delivery serviceability check unavailable.'
            }
          rescue Faraday::Error => e
            Rails.logger.error("[Delhivery] Faraday error querying pincode #{pincode}: #{e.message}")
            {
              pincode: pincode,
              serviceable: false,
              message: 'Delivery serviceability check unavailable.'
            }
          rescue StandardError => e
            Rails.logger.error("[Delhivery] Unexpected error querying pincode #{pincode}: #{e.message}")
            {
              pincode: pincode,
              serviceable: false,
              message: 'Delivery serviceability check unavailable.'
            }
          end

          def resolve_delhivery_credentials
            integration = current_store&.integrations&.find_by(type: 'SpreeDelhivery::Integration', active: true) ||
                          Spree::Integration.find_by(type: 'SpreeDelhivery::Integration', active: true)

            token = integration&.preferred_api_token.presence || ENV['DELHIVERY_API_TOKEN'].presence
            client_name = integration&.preferred_client_name.presence || ENV['DELHIVERY_CLIENT_NAME'].presence || 'DelhiveryClient'
            test_mode = integration ? integration.preferred_test_mode? : (ENV['DELHIVERY_TEST_MODE'] == 'true')

            [token, client_name, test_mode]
          end

          def fetch_carrier_pin_data(base_url, api_token, pincode)
            conn = Faraday.new(url: base_url) do |f|
              f.options.open_timeout = 5
              f.options.timeout = 8
              f.adapter Faraday.default_adapter
              f.headers['Authorization'] = "Token #{api_token}"
              f.headers['Accept'] = 'application/json'
            end

            response = conn.get('/c/api/pin-codes/json/') do |req|
              req.params['filter_codes'] = pincode
            end

            # Delhivery test credentials frequently query pincode directory on live host
            if response.status == 401 && base_url != 'https://track.delhivery.com'
              conn_live = Faraday.new(url: 'https://track.delhivery.com') do |f|
                f.options.open_timeout = 5
                f.options.timeout = 8
                f.adapter Faraday.default_adapter
                f.headers['Authorization'] = "Token #{api_token}"
                f.headers['Accept'] = 'application/json'
              end
              response = conn_live.get('/c/api/pin-codes/json/') do |req|
                req.params['filter_codes'] = pincode
              end
            end

            unless response.success?
              return {
                serviceable: false,
                pincode: pincode,
                message: 'Delivery serviceability check unavailable.'
              }
            end

            data = JSON.parse(response.body) rescue {}
            codes = data['delivery_codes'] || []
            match = codes.find { |c| c.dig('postal_code', 'pin').to_s == pincode }

            if match.nil? || match['postal_code'].blank?
              return {
                serviceable: false,
                pincode: pincode,
                message: 'Delivery is currently unavailable to this PIN code.'
              }
            end

            { serviceable: true, postal_code: match['postal_code'] }
          end

          def format_location_details(postal_code)
            raw_city = postal_code['city'].to_s.strip
            city_name = raw_city.gsub(/\s+(S\.?O|B\.?O|H\.?O)\.?$/i, '').strip.titleize

            raw_dist = postal_code['district'].to_s.strip
            dist_name = raw_dist.gsub(/\s+District$/i, '').strip.titleize

            state_code = (postal_code['state_code'] || postal_code['state']).to_s.strip.upcase
            state_name = INDIA_STATE_MAP[state_code] || state_code.titleize

            [city_name, dist_name, state_name, state_code]
          end

          def resolve_verified_tat(base_url, api_token, postal_code, dest_pin)
            if postal_code['expected_tat'].present? && postal_code['expected_tat'].to_i.positive?
              return postal_code['expected_tat'].to_i
            end

            source_pin = current_store&.default_stock_location&.zipcode.presence ||
                         Spree::StockLocation.where(active: true).where.not(zipcode: nil).first&.zipcode
            return nil if source_pin.blank?

            conn = Faraday.new(url: base_url) do |f|
              f.options.open_timeout = 3
              f.options.timeout = 5
              f.adapter Faraday.default_adapter
              f.headers['Authorization'] = "Token #{api_token}"
              f.headers['Accept'] = 'application/json'
            end

            resp = conn.get('/api/dc/expected_tat') do |req|
              req.params['origin_pin'] = source_pin
              req.params['destination_pin'] = dest_pin
              req.params['mot'] = 'S'
              req.params['pdt'] = 'Pre-paid'
            end

            if resp.success?
              data = JSON.parse(resp.body) rescue {}
              tat = data.dig('data', 'tat') || data['tat']
              return tat.to_i if tat.present? && tat.to_i.positive?
            end

            nil
          rescue StandardError => e
            Rails.logger.debug("[Delhivery] Expected TAT query non-fatal: #{e.message}")
            nil
          end
        end
      end
    end
  end
end

