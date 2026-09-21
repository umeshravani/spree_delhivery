# frozen_string_literal: true

module Spree
  class PaymentMethod < Spree::Base
    class DelhiveryCod < Spree::PaymentMethod
      def actions
        %w{capture void}
      end

      def can_capture?(payment)
        ['checkout', 'pending'].include?(payment.status)
      end

      def can_void?(payment)
        payment.status != 'void'
      end

      def authorize(*)
        simulated_successful_billing_response
      end

      def purchase(*)
        simulated_successful_billing_response
      end

      def capture(*)
        simulated_successful_billing_response
      end

      def cancel(*, **)
        simulated_successful_billing_response
      end

      def void(*)
        simulated_successful_billing_response
      end

      def credit(*)
        simulated_successful_billing_response
      end

      def source_required?
        false
      end

      def payment_source_class
        nil
      end

      def auto_capture?
        false
      end

      def method_type
        'spree_delhivery_cod'
      end

      def session_required?
        false
      end

      private

      def simulated_successful_billing_response
        Spree::PaymentResponse.new(true, '', {}, {})
      end
    end
  end
end
