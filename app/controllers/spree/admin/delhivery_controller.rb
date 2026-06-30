module Spree
  module Admin
    class DelhiveryController < Spree::Admin::BaseController
      # Skip load_shipment for create_pickup because that action uses a StockLocation ID
      before_action :load_shipment, except: [:create_pickup]

      def create_pickup
        stock_id = params[:id]
        @stock_location = if stock_id.to_s.start_with?('stl_') && Spree::StockLocation.respond_to?(:find_by_prefix_id)
                            Spree::StockLocation.find_by_prefix_id(stock_id)
                          else
                            Spree::StockLocation.find(stock_id)
                          end
        
        service = SpreeDelhivery::PickupService.new(@stock_location, count: 5)
        result = service.call

        if result.success?
          flash[:success] = result.message
        else
          flash[:error] = "Pickup Failed: #{result.message}"
        end
        
        # Turbo Fix for seamless UI updates
        redirect_to spree.edit_admin_stock_location_path(@stock_location), status: :see_other
      end
  
      def create_manifest
        sender = SpreeDelhivery::ShipmentSender.new(@shipment)
        result = sender.call

        if result.success?
          # Force the shipment from 'pending' directly to 'shipped' on a successful API response
          ActiveRecord::Base.transaction do
            @shipment.update_columns(
              state: 'shipped',
              shipped_at: @shipment.shipped_at || Time.current
            )
            # Log all inventory units out of warehouse stock management
            @shipment.inventory_units.where.not(state: 'shipped').update_all(state: 'shipped')
            # Trigger downstream order pipeline status calculations
            @shipment.order.updater.update
          end

          flash[:success] = "Shipment Manifested! Waybill: #{@shipment.delhivery_waybill}"
        else
          flash[:error] = "Delhivery Error: #{result.error}"
        end

        # Turbo Fix
        redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
      end

      def delhivery_cancel
        result = SpreeDelhivery::ShipmentCanceler.new(@shipment).call

        if result.success?
          flash[:success] = "Shipment Waybill Voided Successfully."
        else
          flash[:error] = "Delhivery Error: #{result.error}"
        end

        # Turbo Fix
        redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
      end

      def download_label
        if @shipment.delhivery_label_url.present?
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
             redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
          end
        end
      end
      
      def sync_tracking
        result = SpreeDelhivery::ShipmentTracker.new(@shipment).call
        current_status = result.status.to_s.upcase

        raw_data_string = result.data.inspect.upcase if result.data
        
        is_cancelled = current_status.include?("CANCEL") || 
                       current_status.include?("VOID") || 
                       (raw_data_string && (raw_data_string.include?("CANCEL") || raw_data_string.include?("VOID")))

        if is_cancelled
          ActiveRecord::Base.transaction do
            @shipment.update_columns(
              delhivery_waybill: nil, tracking: nil, tracking_status: "CANCELLED",
              state: "ready", shipped_at: nil
            )
            @shipment.inventory_units.update_all(state: "on_hand")
            @shipment.order.updater.update
          end

          flash[:success] = "Remote cancellation detected. Waybill cleared and shipment reset to Ready."
          redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
          return
        end

        # THE COD AUTO-CAPTURE ENGINE
        is_delivered = current_status.include?("DELIVERED") || 
                       (raw_data_string && raw_data_string.include?("DELIVERED"))

        if is_delivered
          ActiveRecord::Base.transaction do
            # Find any pending COD payments on this order and capture them
            @shipment.order.payments.valid.where(state: ['pending', 'checkout']).each do |payment|
              if payment.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod'
                payment.capture!
                Rails.logger.info "[Delhivery] Auto-captured COD Payment #{payment.number} for Order #{@shipment.order.number}"
              end
            end
            
            # Crash Prevention: Spree doesn't natively support a 'delivered' state-machine path.
            # We explicitly update columns to avoid NoMethodError on deliver!
            @shipment.update_columns(
              state: 'shipped',
              tracking_status: 'DELIVERED',
              shipped_at: @shipment.shipped_at || Time.current
            )
            
            # Cleanly verify inventory states match deployment metrics
            @shipment.inventory_units.where.not(state: 'shipped').update_all(state: 'shipped')
            
            # Force downstream state engine recalculations (Clears "Balance Due" badge to green Paid)
            @shipment.order.updater.update
          end

          flash[:success] = "Shipment Delivered! COD Payment automatically captured and reconciled."
          redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
          return
        end

        # STANDARD TRACKING UPDATE
        if result.success?
          @shipment.update_column(:tracking_status, current_status)
          flash[:success] = "Status Updated: #{current_status}"
        else
          flash[:error] = "Tracking Error: #{result.error || current_status}"
        end
        
        # Turbo Fix
        redirect_to spree.edit_admin_order_path(@shipment.order), status: :see_other
      end

      private

      def load_shipment
        shipment_param = params[:shipment_id] || params[:id]
        Rails.logger.info "--- [DELHIVERY DEBUG] Processing ID: #{shipment_param} ---"
      
        @shipment = nil
      
        if shipment_param.to_s.start_with?('ful_')
          if Spree::Shipment.respond_to?(:find_by_prefix_id)
            @shipment = Spree::Shipment.find_by_prefix_id(shipment_param)
          else
            Rails.logger.error "--- [DELHIVERY WARNING] 'find_by_prefix_id' method is missing! ---"
          end
        end
      
        @shipment ||= Spree::Shipment.find_by(number: shipment_param)
      
        if @shipment.nil? && shipment_param.to_s.match?(/\A\d+\z/)
          @shipment = Spree::Shipment.find_by(id: shipment_param)
        end
      
        if @shipment.nil?
          Rails.logger.error "--- [DELHIVERY ERROR] No Shipment found for: #{shipment_param} ---"
          flash[:error] = "Shipment not found for ID: #{shipment_param}"
          redirect_to spree.admin_orders_path, status: :see_other
        end
      rescue => e
        Rails.logger.error "--- [DELHIVERY FATAL] #{e.class}: #{e.message} ---"
        flash[:error] = "An unexpected error occurred: #{e.message}"
        redirect_to spree.admin_orders_path, status: :see_other
      end
    end
  end
end
