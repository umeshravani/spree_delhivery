# frozen_string_literal: true

class EnsureSpreeDelhiveryRecords < ActiveRecord::Migration[7.2]
  def up
    Spree::Store.all.each do |store|
      # 1. COD Payment Method
      cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
      cod.name = 'Cash on Delivery (Delhivery COD)' if cod.name.blank?
      cod.active = true
      cod.storefront_visible = true
      cod.save!

      # 2. Delhivery Integration (if not existing)
      integration = store.integrations.find_or_initialize_by(type: 'SpreeDelhivery::Integration')
      integration.name = 'Delhivery' if integration.name.blank?
      integration.save! if integration.new_record?

      # 3. Delivery Profile & Methods
      profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery', store: store) do |p|
        p.default = true
      end
      profile.update!(default: true) unless profile.default?

      origin_group = profile.delivery_origin_groups.first_or_create!

      surface = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_SURFACE', store: store)
      surface.name = 'Delhivery Surface' if surface.name.blank?
      surface.admin_name = 'Delhivery Surface' if surface.admin_name.blank?
      surface.delivery_profile = profile
      surface.delivery_origin_group = origin_group
      surface.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
      surface.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
      surface.available_to_sellers = true
      surface.storefront_visible = true
      surface.save!

      express = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_EXPRESS', store: store)
      express.name = 'Delhivery Express' if express.name.blank?
      express.admin_name = 'Delhivery Express' if express.admin_name.blank?
      express.delivery_profile = profile
      express.delivery_origin_group = origin_group
      express.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
      express.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
      express.available_to_sellers = true
      express.storefront_visible = true
      express.save!
    end
  end

  def down
    # Reversible no-op
  end
end

