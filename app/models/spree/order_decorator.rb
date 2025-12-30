module Spree
    module OrderDecorator
      def self.prepended(base)
        # Hook into the state machine transition
        base.state_machine.after_transition to: :canceled, do: :cancel_delhivery_shipments
      end
  
      private
  
      def cancel_delhivery_shipments
        # Loop through all shipments that have a Delhivery Waybill
        shipments.where.not(delhivery_waybill: nil).each do |shipment|
          
          # 1. Call the API to void the waybill
          client = SpreeDelhivery::Client.new
          response = client.cancel_shipment(shipment.delhivery_waybill)
  
          # 2. Log the result (visible in Rails logs)
          if response['status'] == "True" || response['success'] == true
            Rails.logger.info "[Delhivery] Auto-Cancellation Success for #{shipment.number} (Waybill: #{shipment.delhivery_waybill})"
            
            # Optional: Clear the waybill from our DB so it can be re-shipped if Order is un-canceled
            shipment.update_columns(delhivery_waybill: nil, tracking: nil)
          else
            Rails.logger.error "[Delhivery] Auto-Cancellation FAILED for #{shipment.number}: #{response}"
          end
          
        end
      rescue StandardError => e
        Rails.logger.error "[Delhivery] System Error during Auto-Cancellation: #{e.message}"
      end
    end
  end
  
  # Apply the decorator
  Spree::Order.prepend(Spree::OrderDecorator)