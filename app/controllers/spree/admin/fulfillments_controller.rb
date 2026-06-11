module Spree
    module Admin
      class FulfillmentsController < Spree::Admin::BaseController
        before_action :load_order_and_shipment
  
        def new
          # CALCULATE LIVE RATES FOR THE DROPDOWN
          @available_methods = Spree::ShippingMethod.all.filter_map do |method|
            begin
              rate = @shipment.shipping_rates.find_by(shipping_method_id: method.id)
              cost = rate&.cost || method.calculator.compute(@shipment) || 0
              display_cost = Spree::Money.new(cost, currency: @order.currency).to_s
              
              { id: method.id, name: method.name, cost: cost, display_cost: display_cost }
            rescue NotImplementedError, StandardError
              nil
            end
          end
          
          render layout: false
        end
  
        def create
          # 1. GLOBAL PRICING UPDATE
          if params[:shipping_method_id].present?
            new_method = Spree::ShippingMethod.find_by(id: params[:shipping_method_id])
            
            if new_method && new_method.id != @shipment.selected_shipping_rate&.shipping_method_id
              new_rate = @shipment.shipping_rates.find_or_initialize_by(shipping_method_id: new_method.id)
              if new_rate.new_record?
                new_rate.cost = new_method.calculator.compute(@shipment) || 0
                new_rate.save!
              end
  
              @shipment.shipping_rates.update_all(selected: false)
              new_rate.update_column(:selected, true)
              @shipment.update_column(:cost, new_rate.cost)
              
              # Recalculate order totals safely
              @order.update_with_updater!
            end
          end
  
          # 2. EXECUTE FULFILLMENT
          if params[:fulfillment_type] == 'manual'
            @shipment.tracking = params[:tracking_number]
            @shipment.save!
            
            # BULLETPROOF FIX: Only transition the state if it hasn't been shipped yet!
            unless @shipment.shipped?
              if @shipment.can_ship?
                @shipment.ship!
              else
                # Force bypass if Spree is locked due to "Credit Owed"
                @shipment.update_columns(state: 'shipped', tracking: @shipment.tracking, shipped_at: Time.current)
                @shipment.inventory_units.update_all(state: 'shipped')
                Spree::ShipmentMailer.shipped_email(@shipment.id).deliver_later rescue nil
              end
            end
  
            carrier_name = @shipment.reload.selected_shipping_rate&.name || "Manual Carrier"
            flash[:success] = "Shipment updated to use #{carrier_name}. Pricing synchronized."
  
            redirect_to spree.edit_admin_order_path(@order), status: :see_other
  
          elsif params[:fulfillment_type] == 'delhivery'
            redirect_to spree.delhivery_manifest_admin_shipment_path(@shipment), status: :temporary_redirect
          else
            flash[:error] = "Invalid fulfillment type selected."
            redirect_to spree.edit_admin_order_path(@order), status: :see_other
          end
        end
  
        private
  
        def load_order_and_shipment
          @order = Spree::Order.find_by!(number: params[:order_id])
          @shipment = @order.shipments.find_by!(number: params[:shipment_id])
        end
      end
    end
  end