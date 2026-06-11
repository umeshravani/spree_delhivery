Rails.application.config.after_initialize do
  # Safely register the payment method
  if Rails.application.config.spree.respond_to?(:payment_methods) && Rails.application.config.spree.payment_methods
    Rails.application.config.spree.payment_methods << Spree::PaymentMethod::DelhiveryCod
  end

  # Safely inject HTML partials ONLY if the Storefront is active
  if Spree.respond_to?(:storefront) && Spree.storefront.respond_to?(:partials)
    Spree.storefront.partials.head << 'spree_delhivery/head'
  end
end
