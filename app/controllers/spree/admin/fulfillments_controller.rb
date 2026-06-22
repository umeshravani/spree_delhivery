module Spree
  module Admin
    class FulfillmentsController < Spree::Admin::BaseController
      before_action :load_order_and_shipment

      def new
        # 1. Fetch available shipping rates for the dropdown
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

        # 2. Pre-calculate Live Delhivery Payload Diagnostics for the UI Audit Box
        if defined?(Spree::Integrations::Delhivery) && Spree::Integrations::Delhivery.active.exists?
          @integration = Spree::Integrations::Delhivery.active.first
          
          # Compute Weight
          raw_weight = @shipment.line_items.sum { |li| (li.variant.weight || 0) * li.quantity }
          raw_weight = 0.5 if raw_weight.zero?
          @weight_unit = @integration.preferred_store_weight_unit || 'kg'
          @weight_in_grams = case @weight_unit
                             when 'kg' then raw_weight * 1000
                             when 'lbs' then raw_weight * 453.592
                             when 'g' then raw_weight
                             else raw_weight * 1000
                             end.to_i

          # Compute Volumetric Dimensions (Stacking Rule)
          max_l = 0; max_w = 0; total_h = 0
          @shipment.line_items.each do |line_item|
            v = line_item.variant
            q = line_item.quantity
            max_l = [max_l, (v.depth || 10).to_f].max
            max_w = [max_w, (v.width || 10).to_f].max
            total_h += ((v.height || 10).to_f * q)
          end

          @dim_unit = @integration.preferred_store_dimension_unit || 'cm'
          @dims_cm = [max_l, max_w, total_h].map do |val|
            case @dim_unit
            when 'cm' then val
            when 'in' then val * 2.54
            when 'm' then val * 100
            when 'mm' then val / 10.0
            else val
            end.round(1)
          end

          # Auto-assign packaging recommendation baseline
          # Delhivery Flyers are restricted to small sizes and weights under 2kg (2000g)
          @recommended_packaging = (@weight_in_grams > 2000 || @dims_cm[0] > 30 || @dims_cm[1] > 30) ? "Carton Box" : "Flyer"
        end
        
        render layout: false
      end

      def create
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
            @order.update_with_updater!
          end
        end

        if params[:fulfillment_type] == 'manual'
          ActiveRecord::Base.transaction do
            @shipment.update_columns(
              tracking: params[:tracking_number],
              state: 'shipped',
              shipped_at: @shipment.shipped_at || Time.current
            )
            @shipment.inventory_units.where.not(state: 'shipped').update_all(state: 'shipped')
            @order.updater.update
          end
          Spree::ShipmentMailer.shipped_email(@shipment.id).deliver_later rescue nil
          carrier_name = @shipment.reload.selected_shipping_rate&.name || "Manual Carrier"
          flash[:success] = "Tracking updated successfully via #{carrier_name}."
          redirect_to spree.edit_admin_order_path(@order), status: :see_other

        elsif params[:fulfillment_type] == 'delhivery'
          # Production Feature: Track layout type form input if selected manually
          if params[:delhivery_packaging_type].present?
            # Store package selection if custom meta columns exist on your shipment
            @shipment.update_column(:delhivery_response_data, (@shipment.delhivery_response_data || {}).merge(selected_packaging: params[:delhivery_packaging_type]))
          end
          redirect_to spree.delhivery_manifest_admin_shipment_path(@shipment), status: :temporary_redirect
        else
          flash[:error] = "Invalid fulfillment type selected."
          redirect_to spree.edit_admin_order_path(@order), status: :see_other
        end
      end

      private

      def load_order_and_shipment
        @order = Spree::Order.find_by!(number: params[:order_id])
        # Accommodate direct collection scoping lookups
        @shipment = @order.shipments.find_by(number: params[:shipment_id]) || Spree::Shipment.find_by!(number: params[:shipment_id])
      end
    end
  end
end
