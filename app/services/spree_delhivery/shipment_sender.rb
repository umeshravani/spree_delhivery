module SpreeDelhivery
  class ShipmentSender
    def initialize(shipment)
      @shipment = shipment
      @order = shipment.order
      @address = @order.ship_address
      @client = SpreeDelhivery::Client.new
      @integration = @client.integration
    end

    def call
      return error("Shipment already has a Waybill") if @shipment.delhivery_waybill.present?

      payload = build_payload
      
      # Send API Request
      response = @client.create_shipment(payload)
      
      # Check for explicit success or package success status
      success_status = response['success'] || 
                       (response['packages'].present? && response['packages'][0]['status'] == 'Success')

      if success_status
        pkg_data = response['packages'].first
        
        # 1. Update Data Columns Safely 
        # Using update_columns to bypass Spree callbacks that might confuse the hash response with a model
        @shipment.update_columns(
          tracking: pkg_data['waybill'],
          delhivery_waybill: pkg_data['waybill'],
          delhivery_ref_id: pkg_data['refnum'], 
          delhivery_response_data: response # Rails handles JSON serialization automatically
        )
        
        # 2. Reload object to ensure fresh state
        @shipment.reload 

        # 3. Fire Spree Shipment State Machine
        # This moves state from 'ready' -> 'shipped'
        # It triggers inventory updates and sends the Shipment Email to customer
        if @shipment.can_ship?
          @shipment.ship! 
        end

        # 4. Fetch Label URL immediately
        begin
          label_res = @client.fetch_label(pkg_data['waybill'])
          if label_res['packages'] && label_res['packages'][0]['pdf_download_link']
             @shipment.update_column(:delhivery_label_url, label_res['packages'][0]['pdf_download_link'])
          end
        rescue => e
          Rails.logger.error("Delhivery Label Fetch Failed: #{e.message}")
        end

        return success(@shipment)
      else
        # Extract error message safely from various possible error keys
        error_msg = response['rmk'] || 
                    response.dig('packages', 0, 'remarks')&.join(', ') || 
                    "Unknown Delhivery Error"
        return error(error_msg)
      end
    rescue StandardError => e
      Rails.logger.error(e.backtrace.join("\n"))
      return error(e.message)
    end

    private

    def build_payload
      payment_mode = @order.paid? ? 'Prepaid' : 'COD'
      
      # Sanitization: Ensure phone is exactly 10 digits (removes +91 or 0 prefix)
      phone = @address.phone.to_s.gsub(/[^0-9]/, '').last(10)
      
      # 1. Calculate and Convert Weight to Grams
      total_weight_grams = calculate_total_weight
      
      # 2. Calculate and Convert Dimensions to CM
      dims = calculate_dimensions # Returns [L, W, H] in CM

      {
        pickup_location: {
          name: @integration.preferred_pickup_location_name
        },
        shipments: [
          {
            name: @address.full_name,
            add: [@address.address1, @address.address2].compact.join(', ').truncate(250),
            pin: @address.zipcode,
            city: @address.city,
            state: @address.state&.name || @address.state_name,
            country: 'India',
            phone: phone,
            order: @shipment.number,
            payment_mode: payment_mode,
            products_desc: @shipment.line_items.map { |i| i.variant.name }.join(', ').truncate(50),
            cod_amount: payment_mode == 'COD' ? @order.total.to_f : 0.0,
            total_amount: @order.total.to_f,
            shipping_mode: @integration.preferred_shipping_mode || 'Surface',
            quantity: @shipment.line_items.sum(&:quantity).to_i,
            
            # Dynamic Values
            weight: total_weight_grams,
            shipment_length: dims[0],
            shipment_width: dims[1],
            shipment_height: dims[2]
          }
        ]
      }
    end

    # --- HELPER METHODS FOR CONVERSION ---

    def calculate_total_weight
      # Sum weight of all items in shipment
      raw_weight = @shipment.line_items.sum { |li| (li.variant.weight || 0) * li.quantity }
      
      # Default to 0.5 (store unit) if weight is missing/zero to avoid API errors
      raw_weight = 0.5 if raw_weight.zero?

      unit = @integration.preferred_store_weight_unit || 'kg'

      grams = case unit
              when 'kg' then raw_weight * 1000
              when 'lbs' then raw_weight * 453.592
              when 'oz' then raw_weight * 28.3495
              when 'g' then raw_weight
              else raw_weight * 1000 # Default assumption
              end
      
      grams.to_i
    end

    def calculate_dimensions
      # Logic: Take the largest item's Length & Width, and sum the Heights (Stacking)
      # This provides a reasonable estimation for the box size.
      
      max_l = 0
      max_w = 0
      total_h = 0

      @shipment.line_items.each do |line_item|
        v = line_item.variant
        q = line_item.quantity
        
        # Get raw dimensions (default to 10 if missing)
        l = (v.depth || 10).to_f # Spree often maps depth to length
        w = (v.width || 10).to_f
        h = (v.height || 10).to_f

        # Update max base dimensions
        max_l = [max_l, l].max
        max_w = [max_w, w].max
        
        # Stack height
        total_h += (h * q)
      end

      # Convert to CM
      unit = @integration.preferred_store_dimension_unit || 'cm'
      
      [max_l, max_w, total_h].map do |val|
        cm = case unit
             when 'cm' then val
             when 'in' then val * 2.54
             when 'm' then val * 100
             when 'mm' then val / 10.0
             else val
             end
        cm.round(2)
      end
    end

    def success(shipment)
      OpenStruct.new(success?: true, shipment: shipment)
    end

    def error(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end