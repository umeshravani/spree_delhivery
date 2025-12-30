module SpreeDelhivery
    class ShipmentTracker
      # Simple result object pattern
      Result = Struct.new(:success?, :status, :data)
  
      def initialize(shipment)
        @shipment = shipment
        @client = SpreeDelhivery::Client.new
      end
  
      def call
        unless @shipment.delhivery_waybill.present?
          return Result.new(false, "No Waybill found for Shipment #{@shipment.number}")
        end
  
        begin
          response = @client.track_shipment(@shipment.delhivery_waybill)
          
          # Safe navigation to extract the Shipment object
          # Delhivery structure: { "ShipmentData" => [ { "Shipment" => { ... } } ] }
          shipment_data = response.dig('ShipmentData', 0, 'Shipment')
  
          if shipment_data.present?
            # 1. Extract Status safely
            # "Status" object contains keys like "Status", "StatusDateTime", "RecievedBy"
            current_status = shipment_data.dig('Status', 'Status') || "Unknown"
  
            # 2. Update Database efficiently
            # usage of update_columns avoids triggering callbacks/validations, which is preferred for background sync
            @shipment.update_columns(
              delhivery_response_data: shipment_data,
              tracking_status: current_status
            )
  
            Rails.logger.info "[Delhivery] Synced Shipment #{@shipment.number}: #{current_status}"
            
            return Result.new(true, current_status, shipment_data)
          else
            error_msg = "No Shipment Data found in Delhivery response"
            Rails.logger.warn "[Delhivery] Tracking Failed for #{@shipment.number}: #{error_msg}"
            return Result.new(false, error_msg)
          end
  
        rescue StandardError => e
          Rails.logger.error "[Delhivery] Exception tracking #{@shipment.number}: #{e.message}"
          return Result.new(false, e.message)
        end
      end
    end
  end