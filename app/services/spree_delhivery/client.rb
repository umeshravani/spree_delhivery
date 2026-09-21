# frozen_string_literal: true

require 'faraday'
require 'json'
require 'uri'

module SpreeDelhivery
  class Client
    LIVE_URL    = 'https://track.delhivery.com'
    STAGING_URL = 'https://staging-express.delhivery.com'

    attr_reader :api_token, :client_name, :base_url

    def initialize(api_token:, client_name: nil, test_mode: false)
      @api_token   = api_token.to_s.strip
      @client_name = client_name.to_s.strip
      @base_url    = test_mode ? STAGING_URL : LIVE_URL
    end

    # --- 1. PIN Code Serviceability ---
    def serviceability(pin:)
      response = connection.get('/c/api/pin-codes/json/') do |req|
        req.params['filter_codes'] = pin.to_s.strip
      end

      if response.status == 401 && @base_url != LIVE_URL
        response = connection(LIVE_URL).get('/c/api/pin-codes/json/') do |req|
          req.params['filter_codes'] = pin.to_s.strip
        end
      end

      return false unless response.success?

      data = parse_json(response.body)
      codes = data['delivery_codes'] || []
      codes.any? { |c| c.dig('postal_code', 'pin').to_s == pin.to_s.strip }
    rescue StandardError => e
      Rails.logger.error("[Delhivery] Serviceability error: #{e.message}")
      false
    end

    def check_pincode(pincode)
      serviceability(pin: pincode)
    end

    # --- 2. Live Dynamic Rate Calculation (Kinko API) ---
    def calculate_rate(origin_pin:, destination_pin:, weight_in_grams:, mode: 'E', payment_type: 'Pre-paid')
      response = connection.get('/api/kinko/v1/invoice/charges.json') do |req|
        req.params['md']    = mode # 'E' (Express/Air) or 'S' (Surface)
        req.params['ss']    = 'Delivered'
        req.params['d_pin'] = destination_pin.to_s.strip
        req.params['o_pin'] = origin_pin.to_s.strip
        req.params['cgm']   = [weight_in_grams.to_f, 50.0].max.to_i
        req.params['pt']    = payment_type # 'Pre-paid' or 'COD'
      end

      if response.status == 401 && @base_url != LIVE_URL
        response = connection(LIVE_URL).get('/api/kinko/v1/invoice/charges.json') do |req|
          req.params['md']    = mode
          req.params['ss']    = 'Delivered'
          req.params['d_pin'] = destination_pin.to_s.strip
          req.params['o_pin'] = origin_pin.to_s.strip
          req.params['cgm']   = [weight_in_grams.to_f, 50.0].max.to_i
          req.params['pt']    = payment_type
        end
      end

      return nil unless response.success?

      data = parse_json(response.body)
      first_quote = data.is_a?(Array) ? data.first : data
      total = first_quote&.dig('total_amount')
      total.present? ? total.to_f : nil
    rescue StandardError => e
      Rails.logger.error("[Delhivery] Rate calculation error: #{e.message}")
      nil
    end

    # --- 3. Shipment Booking (CMU Create API) ---
    def create_shipment(payload:)
      active_url = @base_url
      conn = Faraday.new(url: active_url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end

      response = conn.post('/api/cmu/create.json') do |req|
        req.headers['Authorization'] = "Token #{@api_token}"
        req.headers['Accept']        = 'application/json'
        req.body = { format: 'json', data: payload.to_json }
      end

      if response.status == 401 && active_url != LIVE_URL
        active_url = LIVE_URL
        conn = Faraday.new(url: active_url) do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end
        response = conn.post('/api/cmu/create.json') do |req|
          req.headers['Authorization'] = "Token #{@api_token}"
          req.headers['Accept']        = 'application/json'
          req.body = { format: 'json', data: payload.to_json }
        end
      end

      data = parse_json(response.body)

      unless response.success?
        error_msg = data['error'] || data['rmk'] || response.body
        raise Spree::Core::LabelPurchaseRefused, "Delhivery API Error: #{error_msg}"
      end

      pkg = data['packages']&.first
      if pkg.nil? || pkg['status'] != 'Success'
        remarks = Array(pkg&.dig('remarks')).join(', ').presence || data['rmk'] || data['cash_status'] || 'Shipment creation failed'
        raise Spree::Core::LabelPurchaseRefused, "Delhivery rejected shipment: #{remarks}"
      end

      {
        waybill: pkg['waybill'],
        upload_wbn: data['upload_wbn'],
        sort_code: pkg['sort_code']
      }
    end

    # --- 4. Fetch Official Delhivery PDF Label URL ---
    def fetch_packing_slip_url(waybill:)
      response = connection.get('/api/p/packing_slip') do |req|
        req.params['wbns']     = waybill.to_s.strip
        req.params['pdf']      = 'true'
        req.params['pdf_size'] = '4R' # 4x6 standard format that fits edge-to-edge
      end

      if response.status == 401 && @base_url != LIVE_URL
        response = connection(LIVE_URL).get('/api/p/packing_slip') do |req|
          req.params['wbns']     = waybill.to_s.strip
          req.params['pdf']      = 'true'
          req.params['pdf_size'] = '4R'
        end
      end

      if response.success?
        data = parse_json(response.body)
        pkg = data['packages']&.first
        pkg&.dig('pdf_download_link')
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[Delhivery] Packing slip fetch error: #{e.message}")
      nil
    end

    # --- 5. Shipment Cancellation ---
    def cancel_shipment(waybill:)
      response = connection.post('/api/p/edit') do |req|
        req.headers['Authorization'] = "Token #{@api_token}"
        req.headers['Content-Type']  = 'application/json'
        req.body = { waybill: waybill.to_s.strip, cancellation: 'true' }.to_json
      end

      if response.status == 401 && @base_url != LIVE_URL
        response = connection(LIVE_URL).post('/api/p/edit') do |req|
          req.headers['Authorization'] = "Token #{@api_token}"
          req.headers['Content-Type']  = 'application/json'
          req.body = { waybill: waybill.to_s.strip, cancellation: 'true' }.to_json
        end
      end

      response.success?
    rescue StandardError => e
      Rails.logger.error("[Delhivery] Cancel error: #{e.message}")
      false
    end

    # --- 6. Client Warehouse Registration ---
    def register_warehouse(name:, address:, city:, pin:, phone:, registered_name: nil, return_address: nil, return_city: nil, return_pin: nil)
      clean_phone = phone.to_s.gsub(/\D/, '').last(10).presence || '9999999999'
      clean_pin   = pin.to_s.gsub(/\D/, '').strip
      full_addr   = address.to_s.truncate(200)

      warehouse_payload = {
        name: name.to_s.truncate(50),
        registered_name: (registered_name.presence || name).to_s.truncate(50),
        phone: clean_phone,
        address: full_addr,
        city: city.to_s.truncate(50),
        pin: clean_pin,
        country: 'India',
        return_address: (return_address.presence || full_addr).to_s.truncate(200),
        return_city: (return_city.presence || city).to_s.truncate(50),
        return_pin: (return_pin.presence || clean_pin),
        return_country: 'India'
      }

      active_url = @base_url
      conn = Faraday.new(url: active_url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
        f.headers['Authorization'] = "Token #{@api_token}"
        f.headers['Content-Type']  = 'application/json'
        f.headers['Accept']        = 'application/json'
      end

      response = conn.post('/api/backend/clientwarehouse/create/') do |req|
        req.body = warehouse_payload.to_json
      end

      if response.status == 401 && active_url != LIVE_URL
        active_url = LIVE_URL
        conn = Faraday.new(url: active_url) do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
          f.headers['Authorization'] = "Token #{@api_token}"
          f.headers['Content-Type']  = 'application/json'
          f.headers['Accept']        = 'application/json'
        end
        response = conn.post('/api/backend/clientwarehouse/create/') do |req|
          req.body = warehouse_payload.to_json
        end
      end

      # Returns true if created (201) or already exists (400 / 2000)
      response.status == 201 || response.body.to_s.include?('already exists')
    rescue StandardError => e
      Rails.logger.warn("[Delhivery] Warehouse registration warning for #{name}: #{e.message}")
      false
    end

    private

    def connection(url = @base_url)
      Faraday.new(url: url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
        f.headers['Authorization'] = "Token #{@api_token}"
        f.headers['Accept']        = 'application/json'
      end
    end

    def parse_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      {}
    end
  end
end
