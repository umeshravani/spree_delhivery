module Spree
  module Admin
    class DelhiveryController < Spree::Admin::BaseController
      # We skip load_shipment for create_pickup because that action uses a StockLocation ID
      before_action :load_shipment, except: [:create_pickup]

      def create_pickup
        # Spree 5.4 StockLocations use 'stl_...' prefixes, so we must use the prefix finder if available
        stock_id = params[:id]
        @stock_location = if stock_id.to_s.start_with?('stl_') && Spree::StockLocation.respond_to?(:find_by_prefix_id)
                            Spree::StockLocation.find_by_prefix_id(stock_id)
                          else
                            Spree::StockLocation.find(stock_id)
                          end
        
        # Schedule for Tomorrow, 1 Package (Static for now)
        service = SpreeDelhivery::PickupService.new(@stock_location, count: 5)
        result = service.call

        if result.success?
          flash[:success] = result.message
        else
          flash[:error] = "Pickup Failed: #{result.message}"
        end
        
        redirect_back(fallback_location: spree.edit_admin_stock_location_path(@stock_location))
      end
  
      def create_manifest
        sender = SpreeDelhivery::ShipmentSender.new(@shipment)
        result = sender.call

        if result.success?
          # Waybill is usually stored on the shipment or a custom field
          flash[:success] = "Shipment Manifested! Waybill: #{@shipment.delhivery_waybill}"
        else
          flash[:error] = "Delhivery Error: #{result.error}"
        end

        redirect_to spree.edit_admin_order_path(@shipment.order)
      end

      def delhivery_cancel
        result = SpreeDelhivery::ShipmentCanceler.new(@shipment).call

        if result.success?
          flash[:success] = "Shipment Waybill Voided Successfully."
        else
          flash[:error] = "Delhivery Error: #{result.error}"
        end

        redirect_back(fallback_location: spree.edit_admin_order_path(@shipment.order))
      end

      def download_label
        if @shipment.delhivery_label_url.present?
          # allow_other_host is required for Rails 7+ to redirect to external Delhivery URLs
          redirect_to @shipment.delhivery_label_url, allow_other_host: true
        else
          client = SpreeDelhivery::Client.new
          label_res = client.fetch_label(@shipment.delhivery_waybill)
          
          if label_res['packages'].present? && label_res['packages'][0]['pdf_download_link'].present?
             url = label_res['packages'][0]['pdf_download_link']
             @shipment.update(delhivery_label_url: url)
             redirect_to url, allow_other_host: true
          else
             flash[:error] = "Label not generated yet. Please try again later."
             redirect_to spree.edit_admin_order_path(@shipment.order)
          end
        end
      end
      
      def sync_tracking
        result = SpreeDelhivery::ShipmentTracker.new(@shipment).call

        if result.success?
          flash[:success] = "Status Updated: #{result.status}"
        else
          flash[:error] = "Tracking Error: #{result.error || result.status}"
        end
        
        redirect_back(fallback_location: spree.edit_admin_order_path(@shipment.order))
      end

      private

      def load_shipment
        shipment_param = params[:shipment_id] || params[:id]
        Rails.logger.info "--- [DELHIVERY DEBUG] Processing ID: #{shipment_param} ---"
      
        @shipment = nil
      
        # 1. Safely decode Spree 5.4 Prefixed IDs (ful_...)
        # CRITICAL FIX: The method is find_by_prefix_id (singular prefix)
        if shipment_param.to_s.start_with?('ful_')
          if Spree::Shipment.respond_to?(:find_by_prefix_id)
            @shipment = Spree::Shipment.find_by_prefix_id(shipment_param)
          else
            Rails.logger.error "--- [DELHIVERY WARNING] 'find_by_prefix_id' method is missing! ---"
          end
        end
      
        # 2. Fallback: Shipment Number (H...)
        @shipment ||= Spree::Shipment.find_by(number: shipment_param)
      
        # 3. Fallback: Standard Integer ID (Only if it's pure numbers)
        if @shipment.nil? && shipment_param.to_s.match?(/\A\d+\z/)
          @shipment = Spree::Shipment.find_by(id: shipment_param)
        end
      
        # 4. Final check
        if @shipment.nil?
          Rails.logger.error "--- [DELHIVERY ERROR] No Shipment found for: #{shipment_param} ---"
          flash[:error] = "Shipment not found for ID: #{shipment_param}"
          redirect_to spree.admin_orders_path
        end
      rescue => e
        Rails.logger.error "--- [DELHIVERY FATAL] #{e.class}: #{e.message} ---"
        flash[:error] = "An unexpected error occurred: #{e.message}"
        redirect_to spree.admin_orders_path
      end
    end
  end
end
