Rails.application.config.after_initialize do
  # 1. Safely register the custom Delhivery COD Payment Method (Spree 5 standard)
  if defined?(Spree) && Spree.respond_to?(:payment_methods)
    unless Spree.payment_methods.include?(Spree::PaymentMethod::DelhiveryCod)
      Spree.payment_methods << Spree::PaymentMethod::DelhiveryCod
    end
  end

  # 2. Safely inject HTML partials ONLY if the Storefront UI core engine is active
  if defined?(Spree::Storefront) && Spree.respond_to?(:storefront) && Spree.storefront.respond_to?(:partials)
    unless Spree.storefront.partials.head.include?('spree_delhivery/head')
      Spree.storefront.partials.head << 'spree_delhivery/head'
    end
  end
end