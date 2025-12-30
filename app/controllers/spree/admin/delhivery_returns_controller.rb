module Spree
  module Admin
    class DelhiveryReturnsController < Spree::Admin::BaseController
      
      def create_pickup
        @return_auth = Spree::ReturnAuthorization.find(params[:id])
        
        # 1. Validation: Warehouse Name
        if @return_auth.stock_location.delhivery_warehouse_name.blank?
          flash[:error] = "Delhivery Warehouse Name is missing in Stock Location settings."
          redirect_back(fallback_location: admin_order_return_authorizations_path(@return_auth.order))
          return
        end

        # 2. Capture Options from Modal
        extra_options = {
          brand: params[:brand],
          category: params[:category]
        }

        begin
          client = SpreeDelhivery::Client.new
          
          # 3. Call Service
          # Note: Ensure your client.rb's create_return_request accepts the second argument (options)
          response = client.create_return_request(@return_auth, extra_options)

          # 4. Normalize Response
          resp = response.is_a?(HTTParty::Response) ? response.parsed_response : response
          Rails.logger.info "Delhivery Return Response: #{resp.inspect}"

          # 5. Success Check
          is_success = false
          
          # Check 'packages' array (Standard Delhivery Response)
          if resp['packages'].present? && resp['packages'].is_a?(Array)
             first_pkg = resp['packages'].first
             # Success if status is 'Success' OR if we got a valid waybill number
             if first_pkg['status'] == 'Success' || first_pkg['waybill'].to_s.length > 5
               is_success = true
             end
          end

          if is_success
             waybill = resp['packages'].first['waybill']
             ref_id = resp['packages'].first['ref_id']
             
             # Update Database
             @return_auth.update_columns(
               delhivery_waybill: waybill,
               delhivery_ref_id: ref_id
             )
             
             flash[:success] = "Reverse Pickup Scheduled! Waybill: #{waybill}"
          else
             # 6. Granular Error Handling
             error_text = "Unknown Error"
             
             if resp['detail'].present?
                error_text = "Auth/Permission Error: #{resp['detail']}"
             elsif resp['rmk'].present?
                error_text = resp['rmk'] 
             elsif resp['packages'].present? && resp['packages'].first
                pkg = resp['packages'].first
                error_text = pkg['remarks'] || pkg['status'] || "Package Error"
             elsif resp['error'].present?
                error_text = resp['error'].to_s
             end
             
             flash[:error] = "Delhivery Error: #{error_text}"
          end

        rescue StandardError => e
          flash[:error] = "Connection Exception: #{e.message}"
        end

        redirect_back(fallback_location: admin_order_return_authorizations_path(@return_auth.order))
      end

    end
  end
end