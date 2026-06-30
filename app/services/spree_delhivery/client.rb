require 'faraday'
require 'json'
require 'uri'

module SpreeDelhivery
  class Client
    attr_reader :integration, :connection

    def initialize
      @integration = Spree::Integrations::Delhivery.active.first
      raise "Delhivery Integration is not active or configured" unless @integration

      @api_token = @integration.preferred_api_token.to_s.strip
      
      # Determine base URL based on environment logic
      base_url = if @integration.preferred_production_mode
                   'https://track.delhivery.com'
                 else
                   'https://staging-express.delhivery.com'
                 end

      # Initialize thread-safe isolated Faraday instance
      @connection = Faraday.new(url: base_url) do |conn|
        conn.adapter Faraday.default_adapter
      end
    end

    # Fetch Shipping Rate (GET Request)
    def fetch_shipping_rate(source_pin:, dest_pin:, weight_gms:, mode: 'S')
      path = "/api/kinko/v1/invoice/charges/.json"
      api_mode = map_mode(mode)

      params = {
        md: api_mode, 
        ss: 'Delivered', 
        d_pin: dest_pin, 
        o_pin: source_pin, 
        cgm: weight_gms, 
        pt: 'Pre-paid'
      }
      
      data = send_get_request(path, params)
      
      if data.is_a?(Hash) && data['total_amount']
        data['total_amount'].to_f
      elsif data.is_a?(Array) && data.first && data.first['total_amount']
        data.first['total_amount'].to_f
      else
        nil
      end
    rescue => e
      Rails.logger.error "[Delhivery] Rate Exception: #{e.message}"
      nil
    end

    # Calculate TAT (GET Request)
    def calculate_tat(source_pin:, dest_pin:, mode: 'S')
      path = "/api/dc/expected_tat"
      api_mode = map_mode(mode)

      params = { 
        origin_pin: source_pin, 
        destination_pin: dest_pin, 
        mot: api_mode, 
        pdt: 'Pre-paid',
        token: @api_token 
      }
      
      data = send_get_request(path, params)
      data.is_a?(Hash) ? data : nil
    end
    
    # Fetch Pincode Details (GET Request)
    def fetch_pincode_details(pincode)
      path = "/c/api/pin-codes/json/"
      data = send_get_request(path, { filter_codes: pincode })

      find_city = ->(obj) do
        case obj
        when Hash
          return obj if obj.key?('city') || obj.key?(:city)
          obj.each_value { |v| res = find_city.call(v); return res if res }
        when Array
          obj.each { |v| res = find_city.call(v); return res if res }
        end
        nil
      end

      find_city.call(data)
    rescue => e
      Rails.logger.error "[Delhivery] City Error: #{e.message}"
      nil
    end

    # Create Return Shipment (Form-urlencoded submission containing a nested JSON string)
    def create_return_request(return_auth, options = {})
      order = return_auth.order
      stock_location = return_auth.stock_location
      customer_address = order.ship_address
      
      brand_name = options[:brand].presence || @integration.preferred_client_name
      category_name = options[:category].presence || "General"

      clean_phone = ->(p) { p.to_s.gsub(/[^0-9]/, '').last(10) }
      clean_str = ->(s) { s.to_s.gsub(/[^0-9a-zA-Z\s,\.\-]/, ' ').strip.first(100) }
      
      c_phone = clean_phone.call(customer_address.phone)
      w_phone = clean_phone.call(stock_location.phone)
      
      custom_qc_items = []
      
      return_auth.return_items.each do |ri|
        variant = ri.inventory_unit.variant
        
        img_url = "https://via.placeholder.com/150"
        if variant.images.any?
          img_url = variant.images.first.attachment.url(:small) rescue img_url
        elsif variant.product.images.any?
          img_url = variant.product.images.first.attachment.url(:small) rescue img_url
        end

        reason_text = "Customer Return"
        if ri.respond_to?(:return_reason) && ri.return_reason.present?
          reason_text = ri.return_reason.name
        elsif return_auth.respond_to?(:reason) && return_auth.reason.present?
          reason_text = return_auth.reason.name
        end

        custom_qc_items << {
          "item" => variant.name.first(30),
          "description" => variant.product.description&.first(50) || variant.name,
          "images" => [img_url], 
          "return_reason" => reason_text,
          "quantity" => 1,
          "brand" => brand_name,
          "product_category" => category_name,
          "questions" => [] 
        }
      end

      total_weight_gms = 0.0
      return_auth.inventory_units.each do |unit|
        w = unit.variant.weight.to_f
        w = (w < 50) ? w * 1000.0 : w
        total_weight_gms += w
      end
      total_weight_gms = 500 if total_weight_gms < 500

      payload = {
        "shipments" => [
          {
            "client" => @integration.preferred_client_name,
            "order" => return_auth.number,
            "waybill" => "",
            "name" => customer_address.full_name,
            "add" => clean_str.call(customer_address.address1),
            "city" => customer_address.city,
            "state" => customer_address.state&.name || customer_address.state_name,
            "country" => "India",
            "phone" => c_phone,
            "pin" => customer_address.zipcode,
            
            "return_name" => stock_location.name,
            "return_add" => clean_str.call(stock_location.address1),
            "return_city" => stock_location.city,
            "return_state" => stock_location.state&.name || stock_location.state_name,
            "return_country" => "India",
            "return_pin" => stock_location.zipcode,
            "return_phone" => w_phone,
            
            "payment_mode" => "Pickup",
            "products_desc" => "Return #{order.number}",
            "quantity" => return_auth.return_items.count,
            "weight" => total_weight_gms.to_i,
            "total_amount" => 0,
            "shipping_mode" => "Surface",
            "order_date" => Time.current.strftime("%d-%m-%Y"),
            
            "qc_type" => "param",
            "custom_qc" => custom_qc_items
          }
        ],
        "pickup_location" => {
          "name" => stock_location.delhivery_warehouse_name
        }
      }

      Rails.logger.info "[Delhivery] RVP Payload: #{payload.to_json}"
      send_post_form("/api/cmu/create.json", { "format" => "json", "data" => payload.to_json })
    end

    # Forward Shipment (Form-urlencoded payload wrapper)
    def create_shipment(payload_data)
      send_post_form("/api/cmu/create.json", { "format" => "json", "data" => payload_data.to_json })
    end

    # Fetch Wallet Balance (GET Request)
    def fetch_balance
      data = send_get_request("/api/client/get_balance_ledger.json")
      data.is_a?(Hash) ? data['cash_balance'] : nil
    rescue => e
      Rails.logger.error "[Delhivery] Balance Fetch Failed: #{e.message}"
      nil
    end

    def track_shipment(waybill)
      send_get_request("/api/v1/packages/json/", { waybill: waybill })
    end

    def fetch_label(waybill)
      send_get_request("/api/p/packing_slip", { wbns: waybill, pdf: 'true' })
    end

    def create_pickup_request(location_name:, date:, time:, count: 1)
      payload = { pickup_location: location_name, pickup_date: date, pickup_time: time, expected_package_count: count }
      send_post_json("/fm/request/new/", payload)
    end

    def cancel_shipment(waybill)
      send_post_json("/api/p/edit", { waybill: waybill, cancellation: true })
    end

    private

    def map_mode(val)
      str = val.to_s.downcase.strip
      ['express', 'e'].include?(str) ? 'E' : 'S'
    end

    # Generalized GET Unified Helper
    def send_get_request(path, params = {})
      response = @connection.get(path, params, auth_headers)
      parse_response(response)
    rescue => e
      Rails.logger.error "[Delhivery Client] GET Exception on #{path}: #{e.message}"
      { "error" => "Request Failed", "details" => e.message }
    end

    # Generalized Form URL Encoded Helper (For Manifest Creations)
    def send_post_form(path, form_data = {})
      response = @connection.post(path) do |req|
        req.headers = auth_headers.merge('Content-Type' => 'application/x-www-form-urlencoded')
        req.body = URI.encode_www_form(form_data)
      end
      parse_response(response)
    rescue => e
      Rails.logger.error "[Delhivery Client] Form POST Exception on #{path}: #{e.message}"
      { "error" => "Request Failed", "details" => e.message }
    end

    # Generalized Raw JSON POST Helper (For Pickups and Cancellations)
    def send_post_json(path, body_hash = {})
      response = @connection.post(path) do |req|
        req.headers = auth_headers.merge('Content-Type' => 'application/json')
        req.body = body_hash.to_json
      end
      parse_response(response)
    rescue => e
      Rails.logger.error "[Delhivery Client] JSON POST Exception on #{path}: #{e.message}"
      { "error" => "Request Failed", "details" => e.message }
    end

    # Resilient JSON Parser supporting Delhivery Content-Type fallbacks
    def parse_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      { "raw_body" => response.body, "status" => response.status }
    end

    def auth_headers
      { "Authorization" => "Token #{@api_token}", "Accept" => "application/json" }
    end
  end
end
