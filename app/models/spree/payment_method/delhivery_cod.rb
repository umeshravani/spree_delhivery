module Spree
  class PaymentMethod::DelhiveryCod < PaymentMethod
    def source_required?
      false
    end

    def auto_capture?
      false
    end

    def actions
      %w{authorize capture void purchase}
    end

    def can_capture?(payment)
      ['checkout', 'pending'].include?(payment.state)
    end

    def can_void?(payment)
      payment.state != 'void'
    end

    # Satisfies the Spree API and Rails Checkout authorization step
    def authorize(*args)
      ActiveMerchant::Billing::Response.new(true, "Delhivery COD Authorized", {}, {})
    end

    # Satisfies checkout engines that try to purchase immediately
    def purchase(*args)
      ActiveMerchant::Billing::Response.new(true, "Delhivery COD Purchased", {}, {})
    end

    def capture(*args)
      ActiveMerchant::Billing::Response.new(true, "Delhivery COD Captured", {}, {})
    end

    def void(*args)
      ActiveMerchant::Billing::Response.new(true, "Delhivery COD Voided", {}, {})
    end
  end
end