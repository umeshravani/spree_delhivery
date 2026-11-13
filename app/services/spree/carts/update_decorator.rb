# frozen_string_literal: true

module Spree
  module Carts
    module UpdateDecorator
      private

      def assign_address_id(address_type, address_id)
        if cart.public_send(:"#{address_type}_id") == address_id
          # Even if ID matches existing ship_address_id, if the cart has no fulfillments or delivery rates, trigger recalculation
          if address_type == :shipping_address && (cart.fulfillments.empty? || cart.fulfillments.any? { |f| f.delivery_rates.empty? })
            @address_invalidated = true
          end
          return
        end

        with_address_recalc_tracking(address_type) do
          cart.public_send(:"#{address_type}_id=", address_id)
        end
      end

      def try_advance
        return if cart.complete?

        needs_fulfillment_recalc = @address_invalidated ||
                                   @destination_changed ||
                                   (cart.ship_address.present? && (cart.fulfillments.empty? || cart.fulfillments.any? { |f| f.delivery_rates.empty? }))

        if needs_fulfillment_recalc
          cart.recalculate_for_address_change!(keep_selection: !@new_delivery_destination)
        else
          cart.recalculate_totals!
        end
      rescue Spree::Pricing::PriceResolution::ProviderUnavailable, Spree::Tax::ProviderError
        raise
      rescue StandardError => e
        Rails.error.report(e, context: { order_id: cart.id }, source: 'spree.checkout')
      ensure
        warnings = cart.warnings
        begin
          cart.reload
        rescue StandardError
        end
        cart.warnings |= warnings if warnings.present?
      end
    end
  end
end

Spree::Carts::Update.prepend(Spree::Carts::UpdateDecorator)
