# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module Carts
          module PaymentSessionsControllerDecorator
            def create
              with_order_lock do
                payment_method = current_store.payment_methods.find_by_prefix_id!(permitted_params[:payment_method_id])

                # Invalidate any checkout direct payments on the cart (such as COD)
                @cart.payments.with_state('checkout').each do |p|
                  p.invalidate! unless p.store_credit?
                end

                # Recalculate totals so COD fee is removed immediately
                @cart.recalculate_totals!

                amount = permitted_params[:amount].presence || @cart.total_minus_store_credits

                @payment_session = payment_method.create_payment_session(
                  order: @cart,
                  amount: amount,
                  external_data: permitted_params[:external_data] || {}
                )

                if @payment_session.persisted?
                  render json: serialize_resource(@payment_session), status: :created
                else
                  render_errors(@payment_session.errors)
                end
              end
            end
          end
        end
      end
    end
  end
end

Spree::Api::V3::Store::Carts::PaymentSessionsController.prepend(Spree::Api::V3::Store::Carts::PaymentSessionsControllerDecorator)
