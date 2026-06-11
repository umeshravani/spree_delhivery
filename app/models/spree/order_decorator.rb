module Spree
  module OrderDecorator
    def self.prepended(base)
      # Hook 1: Add/Remove COD Surcharge for both Rails (confirm) and Next.js (complete) flows
      base.state_machine.before_transition to: [:confirm, :complete], do: :manage_cod_surcharge
      
      # Hook 2: Auto-void Delhivery waybills if the order is canceled
      base.state_machine.after_transition to: :canceled, do: :cancel_delhivery_shipments
    end

    def manage_cod_surcharge
      # 1. Check if the customer chose Delhivery COD
      is_cod = payments.valid.any? { |p| p.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod' }
      
      # 2. Fetch your Delhivery configuration
      integration = Spree::Integrations::Delhivery.active.first
      surcharge_amount = integration&.preferred_cod_surcharge_amount.to_f

      # 3. Apply or Remove the financial adjustment
      if is_cod && surcharge_amount > 0
        # Destroy any old COD fees to prevent duplicate stacking
        adjustments.where(label: 'COD Surcharge').destroy_all
        
        # Create the new fee
        adjustments.create!(
          order: self,
          adjustable: self, # Apply to the whole order
          label: 'COD Surcharge',
          amount: surcharge_amount,
          state: 'closed', # Prevents Spree's auto-calculator from zeroing it out
          included: false
        )
      else
        # If they switched back to Prepaid, cleanly remove the fee
        adjustments.where(label: 'COD Surcharge').destroy_all
      end

      # Force Spree to recalculate the grand total with the new fee
      updater.update
    end

    private

    def cancel_delhivery_shipments
      shipments.where.not(delhivery_waybill: nil).each do |shipment|
        client = SpreeDelhivery::Client.new
        response = client.cancel_shipment(shipment.delhivery_waybill)

        if response['status'] == "True" || response['success'] == true
          Rails.logger.info "[Delhivery] Auto-Cancellation Success for #{shipment.number}"
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