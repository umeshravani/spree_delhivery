# frozen_string_literal: true

module Spree
  class PaymentMethod < Spree::Base
    class DelhiveryCod < Spree::PaymentMethod
      self.accepts_money_amounts = true

      DELHIVERY_SVG_PATH = File.expand_path('../../assets/images/spree_delhivery/delhivery-icon.svg', __dir__)
      DELHIVERY_PNG_PATH = File.expand_path('../../assets/images/spree_delhivery/delhivery-icon.png', __dir__)

      def self.logo_url
        if File.exist?(DELHIVERY_SVG_PATH)
          "data:image/svg+xml;base64,#{Base64.strict_encode64(File.read(DELHIVERY_SVG_PATH))}"
        elsif File.exist?(DELHIVERY_PNG_PATH)
          "data:image/png;base64,#{Base64.strict_encode64(File.read(DELHIVERY_PNG_PATH))}"
        else
          'https://www.delhivery.com/assets/images/logo.png'
        end
      end

      def self.docs_url
        'https://www.delhivery.com'
      end

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
