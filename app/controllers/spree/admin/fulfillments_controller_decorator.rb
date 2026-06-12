module Spree
  module Admin
    module FulfillmentsControllerDecorator
      def self.prepended(base)
        base.class_eval do
          # Override the action that handles the "Ship" button submission.
          # (Replace :create with :update if your form uses PATCH/PUT)
          alias_method :original_create, :create 

          def create
            @shipment = Spree::Shipment.find_by(number: params[:shipment_id]) || Spree::Shipment.find_by(id: params[:shipment_id])
            
            # If we are doing a manual tracking update on an ALREADY SHIPPED item
            if @shipment && @shipment.shipped? && params[:manual_tracking].present?
              
              # 1. Just update the tracking number directly
              @shipment.update_column(:tracking, params[:tracking_number]) 
              
              # 2. Add a note to the order for historical auditing
              @shipment.order.log_entries.create!(
                details: "Tracking number manually updated to #{params[:tracking_number]} after shipment."
              )

              flash[:success] = "Tracking number successfully updated."
              redirect_to back_url
            else
              # If it's a normal shipment, run the original plugin code
              original_create
            end
          end
        end
      end
    end
  end
end

# Register the decorator safely for Zeitwerk
if defined?(Spree::Admin::FulfillmentsController)
  Spree::Admin::FulfillmentsController.prepend(Spree::Admin::FulfillmentsControllerDecorator)
end
