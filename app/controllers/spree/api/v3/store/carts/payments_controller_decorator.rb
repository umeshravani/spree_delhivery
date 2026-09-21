# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module Carts
          module PaymentsControllerDecorator
            def create
              payment_method = current_store.payment_methods.find_by_prefix_id!(params[:payment_method_id])

              if payment_method.session_required?
                return render_error(
                  code: 'payment_session_required',
                  message: Spree.t('api.v3.payments.session_required'),
                  status: :unprocessable_content
                )
              end

              unless payment_method.available_for_order?(@cart)
                return render_error(
                  code: 'payment_method_unavailable',
                  message: Spree.t('api.v3.payments.method_unavailable'),
                  status: :unprocessable_content
                )
              end

              # Cancel active payment sessions so direct payment takes precedence
              if @cart.respond_to?(:payment_sessions)
                @cart.payment_sessions.where(status: %w[pending processing]).update_all(status: 'canceled')
              end

              amount = params[:amount].presence || @cart.total_minus_store_credits

              @payment = @cart.payments.build(
                payment_method: payment_method,
                amount: amount,
                metadata: params[:metadata].present? ? params[:metadata].to_unsafe_h : {}
              )

              if @payment.save
                # Invalidate any other checkout payments
                @cart.payments.with_state('checkout').where.not(id: @payment.id).each do |p|
                  p.invalidate! unless p.store_credit?
                end

                # Recalculate totals on cart with new payment active (adds COD surcharge if COD)
                @cart.recalculate_totals!

                # Update payment amount to the recalculated total if needed
                new_amount = @cart.total_minus_store_credits
                @payment.update_columns(amount: new_amount) if @payment.amount != new_amount

                render json: Spree.api.payment_serializer.new(@payment, params: serializer_params).to_h, status: :created
              else
                render_errors(@payment.errors)
              end
            end
          end
        end
      end
    end
  end
end

Spree::Api::V3::Store::Carts::PaymentsController.prepend(Spree::Api::V3::Store::Carts::PaymentsControllerDecorator)
