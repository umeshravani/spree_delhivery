module Spree
    module Admin
      module ShipmentsControllerDecorator
        def self.prepended(base)
          # Ensure we can access these methods inside the controller
          base.helper_method :delhivery_integration
        end
  
        # POST /admin/shipments/:id/delhivery_manifest
        def delhivery_manifest
          @shipment = Spree::Shipment.find(params[:id])
          
          # 1. Validation
          unless delhivery_integration
            flash[:error] = "Delhivery Integration is not active."
            return redirect_back(fallback_location: admin_orders_path)
          end
  
          unless @shipment.stock_location.delhivery_warehouse_name.present?
            flash[:error] = "Stock Location is missing 'Delhivery Warehouse Name'. Please configure it first."
            return redirect_to edit_admin_stock_location_path(@shipment.stock_location)
          end
  
          # 2. Build Payload
          # We delegate this complex logic to a dedicated helper method below
          payload = build_delhivery_payload(@shipment)
  
          # 3. Call API
          client = SpreeDelhivery::Client.new
          response = client.create_shipment(payload)
  
          # 4. Handle Response
          if response['packages'].present? && response['packages'][0]['status'] == 'Success'
            # Success!
            waybill = response['packages'][0]['waybill']
            ref_id  = response['packages'][0]['refnum'] # Our shipment number
            
            @shipment.update!(
              delhivery_waybill: waybill,
              delhivery_ref_id: ref_id,
              tracking: waybill,
              state: 'shipped', # Mark as shipped in Spree immediately
              shipped_at: Time.current,
              delhivery_response_data: response
            )
  
            flash[:success] = "Delhivery Waybill Generated: #{waybill}"
          else
            # Error
            error_msg = response['error'] || response['packages']&.first&.fetch('remarks', nil) || "Unknown API Error"
            flash[:error] = "Delhivery Failed: #{error_msg}"
          end
  
          redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
        rescue StandardError => e
          flash[:error] = "System Error: #{e.message}"
          redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
        end
  
        # POST /admin/shipments/:id/delhivery_track
        def delhivery_track
          @shipment = Spree::Shipment.find(params[:id])
          
          if @shipment.delhivery_waybill.blank?
            flash[:error] = "No Waybill found to track."
          else
            client = SpreeDelhivery::Client.new
            response = client.track_shipment(@shipment.delhivery_waybill)
            
            # Parse flexible response (sometimes Array, sometimes Hash)
            data = response.is_a?(Array) ? response.first : response
            
            if data && data['ShipmentData']
              status = data['ShipmentData'][0]['Shipment']['Status']['Status'] rescue "Unknown"
              @shipment.update(tracking_status: status)
              flash[:success] = "Tracking Updated: #{status}"
            else
              flash[:warning] = "Tracking info not available yet."
            end
          end
          
          redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
        end
  
        # POST /admin/shipments/:id/delhivery_cancel
        def delhivery_cancel
          @shipment = Spree::Shipment.find(params[:id])
          
          client = SpreeDelhivery::Client.new
          response = client.cancel_shipment(@shipment.delhivery_waybill)
  
          # Delhivery cancellation response varies, usually checks for success code
          if response['status'] == "True" || response['success'] == true
            @shipment.update(
              delhivery_waybill: nil, 
              tracking: nil,
              state: 'ready' # Revert state so we can ship again
            )
            flash[:success] = "Shipment Cancelled successfully."
          else
            flash[:error] = "Cancellation Failed: #{response['error'] || response['message']}"
          end
          
          redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
        end
  
        # GET /admin/shipments/:id/delhivery_label
        def delhivery_label
          @shipment = Spree::Shipment.find(params[:id])
          
          client = SpreeDelhivery::Client.new
          response = client.fetch_label(@shipment.delhivery_waybill)
          
          # API usually returns a JSON with a 'packages' array containing a 'pdf_download_link'
          # Or sometimes raw PDF data depending on endpoint. 
          # Assuming the 'packing_slip' endpoint returns JSON with a URL:
          if response['packages'].present? && response['packages'][0]['pdf_download_link'].present?
            redirect_to response['packages'][0]['pdf_download_link'], allow_other_host: true
          else
            flash[:error] = "Label URL not found in response."
            redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
          end
        end
  
        private
  
        def delhivery_integration
          @delhivery_integration ||= Spree::Integrations::Delhivery.active.first
        end
  
        # ---------------------------------------------------------
        # PAYLOAD BUILDER
        # This maps Spree Shipment Data -> Delhivery JSON Format
        # ---------------------------------------------------------
        def build_delhivery_payload(shipment)
          order = shipment.order
          address = order.shipping_address
          location = shipment.stock_location
  
          # Calculate Weight (Convert to Grams if needed)
          # Assuming Spree weight is in KG. 
          total_weight_kgs = shipment.line_items.sum { |li| li.variant.weight.to_f * li.quantity }
          total_weight_gms = (total_weight_kgs * 1000).to_i
          total_weight_gms = 500 if total_weight_gms < 500 # Minimum 500g
  
          payment_mode = order.paid? ? 'Pre-paid' : 'COD'
          cod_amount = payment_mode == 'COD' ? order.total.to_f : 0.0
  
          {
            shipments: [
              {
                name: "#{address.firstname} #{address.lastname}",
                add: "#{address.address1} #{address.address2}",
                pin: address.zipcode,
                city: address.city,
                state: address.state&.name || address.state_text,
                country: address.country&.iso || "IN",
                phone: address.phone,
                order: shipment.number, # Ref ID
                payment_mode: payment_mode,
                return_pin: location.zipcode,
                return_city: location.city,
                return_phone: location.phone,
                return_add: location.address1,
                products_desc: shipment.line_items.map { |li| li.product.name }.join(', '),
                hsn_code: "", # Add logic here if you store HSN codes on products
                cod_amount: cod_amount,
                order_date: order.completed_at&.strftime('%Y-%m-%d'),
                total_amount: order.total.to_f,
                seller_inv_date: Time.current.strftime('%Y-%m-%d'),
                seller_name: location.delhivery_warehouse_name, # Critical!
                seller_add: "#{location.address1} #{location.city}",
                seller_inv: shipment.number,
                quantity: shipment.line_items.sum(&:quantity),
                waybill: "", # Blank for creation
                shipment_width: 10,  # Default or fetch from products
                shipment_height: 10, # Default
                shipment_depth: 10,  # Default
                shipment_weight: total_weight_gms
              }
            ],
            pickup_location: {
              name: location.delhivery_warehouse_name,
              add: location.address1,
              city: location.city,
              pin_code: location.zipcode,
              country: location.country&.iso || "IN",
              phone: location.phone
            }
          }
        end
  
      end
    end
  end
  
  # Apply the decoration
  Spree::Admin::ShipmentsController.prepend(Spree::Admin::ShipmentsControllerDecorator)