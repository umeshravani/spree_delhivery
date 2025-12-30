module SpreeDelhivery
    class ShipmentCanceler
      def initialize(shipment)
        @shipment = shipment
        @client = SpreeDelhivery::Client.new
      end
  
      def call
        waybill = @shipment.delhivery_waybill
        return error("No Waybill found to cancel") unless waybill.present?
  
        # 1. Call API
        begin
          response = @client.cancel_shipment(waybill)
        rescue StandardError => e
          return error("API Connection Error: #{e.message}")
        end
  
        # Delhivery success response is usually { "status" => true/false, ... } or "success" => true
        # Sometimes it returns specific codes. We check general success/failure keys.
        api_success = response['success'] || response['status'] == true || response['status'] == "Success"
  
        if api_success
          # 2. Clear Data & Revert State in Spree
          # We use update_columns to skip state machine transitions/validations
          @shipment.update_columns(
            tracking: nil,
            delhivery_waybill: nil,
            delhivery_ref_id: nil,
            delhivery_label_url: nil,
            delhivery_response_data: nil,
            state: 'ready',      # Move back to Ready
            shipped_at: nil      # Clear the shipped timestamp
          )
  
          # 3. Update the Order's overall shipment state
          # This ensures the order status bar updates correctly
          @shipment.order.updater.update_shipment_state
          @shipment.order.save
  
          return success
        else
          return error(response['error'] || response['message'] || "Failed to cancel at Delhivery")
        end
      rescue StandardError => e
        return error(e.message)
      end
  
      private
  
      def success
        OpenStruct.new(success?: true)
      end
  
      def error(msg)
        OpenStruct.new(success?: false, error: msg)
      end
    end
  end