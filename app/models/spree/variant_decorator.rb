# frozen_string_literal: true

module Spree
  module VariantDecorator
    def resolved_delivery_profile
      profile = super
      if profile.nil? || (profile.is_a?(Spree::DeliveryProfiles::Shipping) && profile.delivery_methods.none?)
        fallback = product&.resolved_delivery_profile ||
                   (store && Spree::DeliveryProfile.default_for(store)) ||
                   Spree::DeliveryProfiles::Shipping.find_by(name: 'Delhivery', store: store) ||
                   Spree::DeliveryProfiles::Shipping.where(store: store).detect { |p| p.delivery_methods.any? }
        fallback || profile
      else
        profile
      end
    end
  end
end

Spree::Variant.prepend(Spree::VariantDecorator)
