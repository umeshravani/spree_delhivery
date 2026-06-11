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
        # --- IMPROVED ERROR HANDLING ---
        # 1. Extract the deep error message first (it's more accurate than 'rmk')
        raw_error = response.dig('packages', 0, 'remarks')&.join(', ') || response['rmk'] || "Unknown Error"
        
        # 2. Map known API errors to friendly user messages
        friendly_error = case raw_error.to_s.downcase
                         when /insufficient balance/
                           # Fetch live balance to show the user
                           current_bal = @client.fetch_balance rescue nil
                           msg = "Authorization Failed: Insufficient Delhivery Wallet Balance."
                           msg += " Current Balance: ₹#{current_bal}." if current_bal
                           msg + " Please recharge."
                         when /duplicate/
                           "Duplicate Order: This order ID has already been processed."
                         when /pincode/
                           "Serviceability Error: Pincode (#{@address.zipcode}) not serviceable."
                         else
                           "Delhivery Error: #{raw_error}"
                         end

        return error(friendly_error)
      end
    rescue StandardError => e
      Rails.logger.error(e.backtrace.join("\n"))
      return error(e.message)
    end

    private

    def build_payload
      # --- ROBUST PAYMENT MODE DETECTION ---
      # Instead of relying on order.paid?, look at valid payments assigned to the order
      is_cod_payment = @order.payments.valid.any? do |payment|
        payment.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod'
      end

      payment_mode = is_cod_payment ? 'COD' : 'Prepaid'
      
      # Sanitization: Ensure phone is exactly 10 digits (removes +91 or 0 prefix)
      phone = @address.phone.to_s.gsub(/[^0-9]/, '').last(10)
      
      # 1. Calculate and Convert Weight to Grams
      total_weight_grams = calculate_total_weight
      
      # 2. Calculate and Convert Dimensions to CM
      dims = calculate_dimensions # Returns [L, W, H] in CM

      # 3. Detect Shipping Mode dynamically from Customer Choice
      shipping_method_name = @shipment.shipping_method&.name.to_s.downcase
      
      final_shipping_mode = if shipping_method_name.include?('express')
                              'Express'
                            elsif shipping_method_name.include?('surface')
                              'Surface'
                            else
                              # Fallback to Admin Setting if name is generic (e.g. "Free Shipping")
                              @integration.preferred_shipping_mode || 'Surface'
                            end

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
            
            # --- DYNAMIC COD COLLECTION VALUES ---
            cod_amount: payment_mode == 'COD' ? @order.total.to_f : 0.0,
            total_amount: @order.total.to_f,
            
            # Use the detected mode ('Express' or 'Surface')
            shipping_mode: final_shipping_mode,
            quantity: @shipment.line_items.sum(&:quantity).to_i,
            
            # Dynamic Values
            weight: total_weight_grams,
            shipment_length: dims[0],
            shipment_width: dims[1],
            shipment_height: dims[2],
            
            # Client Name (Dynamic based on settings)
            client: @integration.preferred_client_name
          }
        ]
      }
    end

    def calculate_total_weight
      raw_weight = @shipment.line_items.sum { |li| (li.variant.weight || 0) * li.quantity }
      raw_weight = 0.5 if raw_weight.zero?

      unit = @integration.preferred_store_weight_unit || 'kg'

      grams = case unit
              when 'kg' then raw_weight * 1000
              when 'lbs' then raw_weight * 453.592
              when 'oz' then raw_weight * 28.3495
              when 'g' then raw_weight
              else raw_weight * 1000
              end
      
      grams.to_i
    end

    def calculate_dimensions
      max_l = 0
      max_w = 0
      total_h = 0

      @shipment.line_items.each do |line_item|
        v = line_item.variant
        q = line_item.quantity
        
        l = (v.depth || 10).to_f
        w = (v.width || 10).to_f
        h = (v.height || 10).to_f

        max_l = [max_l, l].max
        max_w = [max_w, w].max
        total_h += (h * q)
      end

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