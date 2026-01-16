require 'httparty'
require 'json'
require 'uri'

module SpreeDelhivery
  class Client
    include HTTParty
    
    # Base Configuration
    base_uri 'https://track.delhivery.com' 

    attr_reader :integration

    def initialize
      @integration = Spree::Integrations::Delhivery.active.first
      raise "Delhivery Integration is not active or configured" unless @integration

      @api_token = @integration.preferred_api_token.to_s.strip
      
      # Environment Logic
      if @integration.preferred_production_mode
        self.class.base_uri 'https://track.delhivery.com'
        @env_name = "PRODUCTION"
      else
        self.class.base_uri 'https://staging-express.delhivery.com'
        @env_name = "STAGING"
      end
    end

    # Fetch Shipping Rate
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
      
      response = self.class.get(path, query: params, headers: auth_headers)
      data = response.parsed_response 
      
      if data.is_a?(Hash) && data['total_amount']
        return data['total_amount'].to_f
      elsif data.is_a?(Array) && data.first && data.first['total_amount']
        return data.first['total_amount'].to_f
      else
        return nil
      end
    rescue => e
      Rails.logger.error "[Delhivery] Rate Exception: #{e.message}"
      nil
    end

    # Calculate TAT
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
      
      response = self.class.get(path, query: params, headers: auth_headers)
      response.parsed_response.is_a?(Hash) ? response.parsed_response : nil
    rescue => e
      Rails.logger.error "[Delhivery] TAT Error: #{e.message}"
      nil
    end
    
    # Fetch Pincode Details
    def fetch_pincode_details(pincode)
      path = "/c/api/pin-codes/json/"
      response = self.class.get(path, query: { filter_codes: pincode }, headers: auth_headers)
      data = response.parsed_response 

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

    # Create Return Shipment
    def create_return_request(return_auth, options = {})
      order = return_auth.order
      stock_location = return_auth.stock_location
      customer_address = order.ship_address
      
      # Defaults if not provided
      brand_name = options[:brand].presence || @integration.preferred_client_name
      category_name = options[:category].presence || "General"

      # Data Cleaning
      clean_phone = ->(p) { p.to_s.gsub(/[^0-9]/, '').last(10) }
      clean_str = ->(s) { s.to_s.gsub(/[^0-9a-zA-Z\s,\.\-]/, ' ').strip.first(100) }
      
      c_phone = clean_phone.call(customer_address.phone)
      w_phone = clean_phone.call(stock_location.phone)
      
      # Construct Custom QC Items
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
          "brand" => brand_name,       # <--- DYNAMIC
          "product_category" => category_name, # <--- DYNAMIC
          "questions" => [] 
        }
      end

      # Calculate Weight
      total_weight_gms = 0.0
      return_auth.inventory_units.each do |unit|
        w = unit.variant.weight.to_f
        w = (w < 50) ? w * 1000.0 : w
        total_weight_gms += w
      end
      total_weight_gms = 500 if total_weight_gms < 500

      # Payload
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

      response = self.class.post(
        "/api/cmu/create.json",
        body: { "format" => "json", "data" => payload.to_json },
        headers: { "Authorization" => "Token #{@api_token}" }
      )
      
      JSON.parse(response.body) rescue { "error" => "Invalid JSON Response" }

    rescue StandardError => e
      Rails.logger.error "Delhivery Return Exception: #{e.message}"
      { "error" => e.message }
    end

    # 5. Forward Shipment
    def create_shipment(payload_data)
      response = self.class.post("/api/cmu/create.json", 
        body: { "format" => "json", "data" => payload_data.to_json }, 
        headers: { "Authorization" => "Token #{@api_token}" }
      )
      JSON.parse(response.body) rescue {}
    end

    # 6. Fetch Wallet Balance
    def fetch_balance
      # This is the standard endpoint for checking Delhivery wallet balance
      response = self.class.get("/api/client/get_balance_ledger.json", headers: auth_headers)
      
      if response.success? && response.parsed_response.is_a?(Hash)
        # Returns format like: { "cash_balance" => "150.00", ... }
        return response.parsed_response['cash_balance'] 
      end
      nil
    rescue => e
      Rails.logger.error "[Delhivery] Balance Fetch Failed: #{e.message}"
      nil
    end

    def track_shipment(waybill)
      send_get_request("/api/v1/packages/json/?waybill=#{waybill}")
    end

    def fetch_label(waybill)
      send_get_request("/api/p/packing_slip?wbns=#{waybill}&pdf=true")
    end

    def create_pickup_request(location_name:, date:, time:, count: 1)
      payload = { pickup_location: location_name, pickup_date: date, pickup_time: time, expected_package_count: count }
      post_json("/fm/request/new/", payload)
    end

    def cancel_shipment(waybill)
      post_json("/api/p/edit", { waybill: waybill, cancellation: true })
    end

    private

    def map_mode(val)
      str = val.to_s.downcase.strip
      ['express', 'e'].include?(str) ? 'E' : 'S'
    end

    def send_get_request(path, params = {})
      response = self.class.get(path, query: params, headers: auth_headers)
      response.parsed_response
    rescue => e
      { "error" => "Request Failed", "details" => e.message }
    end

    def post_json(path, body = {})
      response = self.class.post(path, body: body.to_json, headers: auth_headers.merge('Content-Type' => 'application/json'))
      response.parsed_response
    rescue => e
       { "error" => "Request Failed", "details" => e.message }
    end

    def auth_headers
      { "Authorization" => "Token #{@api_token}", "Accept" => "application/json" }
    end
  end
end
