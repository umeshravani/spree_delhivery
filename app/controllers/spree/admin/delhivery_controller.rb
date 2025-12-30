module Spree
    module Admin
      class DelhiveryController < Spree::Admin::BaseController
        before_action :load_shipment
      
      def create_pickup
        @stock_location = Spree::StockLocation.find(params[:id])
        
        # Simple Logic: Schedule for Tomorrow, 1 Package (You can make this dynamic later)
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
            flash[:success] = "Shipment Manifested! Waybill: #{result.shipment.delhivery_waybill}"
          else
            flash[:error] = "Delhivery Error: #{result.error}"
          end
  
          # Reload the order edit page
          redirect_to spree.edit_admin_order_path(@shipment.order)
        end

        def delhivery_cancel
          result = SpreeDelhivery::ShipmentCanceler.new(@shipment).call
  
          if result.success?
            flash[:success] = "Shipment Waybill Voided Successfully."
          else
            flash[:error] = "Delhivery Error: #{result.error}"
          end
  
          redirect_back(fallback_location: edit_admin_order_path(@shipment.order))
        end
  
        def download_label
          if @shipment.delhivery_label_url.present?
            redirect_to @shipment.delhivery_label_url, allow_other_host: true
          else
            # Fallback: Try fetching again if URL expired or missing
            client = SpreeDelhivery::Client.new
            label_res = client.fetch_label(@shipment.delhivery_waybill)
            
            if label_res['packages'].present? && label_res['packages'][0]['pdf_download_link'].present?
               url = label_res['packages'][0]['pdf_download_link']
               @shipment.update(delhivery_label_url: url)
               redirect_to url, allow_other_host: true
            else
               flash[:error] = "Label not generated yet. Please try again later."
               redirect_to edit_admin_order_path(@shipment.order)
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
          # Spree 5 uses 'id' or 'number' for shipments
          @shipment = Spree::Shipment.find_by(number: params[:id]) || Spree::Shipment.find_by(id: params[:id])
          unless @shipment
            flash[:error] = "Shipment not found"
            redirect_to admin_orders_path
          end
        end
      end
    end
  end