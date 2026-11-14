# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module CartsControllerDecorator
          private

          def render_cart(status: :ok)
            if @cart && !@cart.complete? && @cart.ship_address.present? && @cart.line_items.any? && (@cart.fulfillments.empty? || @cart.fulfillments.any? { |f| f.delivery_rates.empty? })
              begin
                @cart.recalculate_for_address_change!
              rescue StandardError => e
                Rails.error.report(e, context: { order_id: @cart.id }, source: 'spree.checkout.recalculate')
              end
            end

            super
          end
        end
      end
    end
  end
end

Spree::Api::V3::Store::CartsController.prepend(Spree::Api::V3::Store::CartsControllerDecorator)

