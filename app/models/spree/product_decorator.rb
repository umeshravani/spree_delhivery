# frozen_string_literal: true

module Spree
  module ProductDecorator
    def resolved_delivery_profile
      profile = super
      if profile.nil? || (profile.is_a?(Spree::DeliveryProfiles::Shipping) && profile.delivery_methods.none?)
        fallback = (store && Spree::DeliveryProfile.default_for(store)) ||
                   Spree::DeliveryProfiles::Shipping.find_by(name: 'Delhivery', store: store) ||
                   Spree::DeliveryProfiles::Shipping.where(store: store).detect { |p| p.delivery_methods.any? }
        fallback || profile
      else
        profile
      end
    end
  end
end

Spree::Product.prepend(Spree::ProductDecorator)
