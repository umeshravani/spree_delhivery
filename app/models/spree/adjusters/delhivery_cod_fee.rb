# frozen_string_literal: true

module Spree
  module Adjusters
    class DelhiveryCodFee < Base
      def update
        return unless order.persisted?

        active_payments = order.payments.reset.valid.to_a
        cod_payment = active_payments.find do |p|
          p.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod'
        end

        # If an active payment session exists (e.g. Razorpay, Stripe), COD is not active
        if order.respond_to?(:payment_sessions) && order.payment_sessions.where(status: %w[pending processing]).exists?
          cod_payment = nil
        end

        fee = order.fees.find_or_initialize_by(label: 'COD Surcharge')

        if cod_payment
          integration = order.store.integrations.active.find_by(type: 'SpreeDelhivery::Integration')
          surcharge = integration&.preferred_cod_surcharge.to_f

          if surcharge > 0
            fee.kind = 'cod'
            fee.amount = surcharge
            fee.save! if fee.changed? || fee.new_record?
          else
            fee.destroy! if fee.persisted?
          end
        else
          fee.destroy! if fee.persisted?
        end
      end
    end
  end
end
