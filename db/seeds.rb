# frozen_string_literal: true

stores = Spree::Store.all.presence || [Spree::Store.default]

api_token = ENV['DELHIVERY_API_TOKEN'].presence
client_name = ENV['DELHIVERY_CLIENT_NAME'].presence || 'DelhiveryClient'
test_mode = ENV['DELHIVERY_TEST_MODE'] == 'true' || ENV['DELHIVERY_TEST_MODE'].nil?

stores.each do |store|
  next unless store

  # 1. Integration Record (Required before DeliveryMethod validation)
  integration = store.integrations.find_or_initialize_by(type: 'SpreeDelhivery::Integration')
  integration.name = 'Delhivery' if integration.name.blank?
  integration.active = true
  integration.preferred_api_token = api_token if api_token.present? || integration.preferred_api_token.blank?
  integration.preferred_api_token = 'test_delhivery_api_token_123' if integration.preferred_api_token.blank?
  integration.preferred_client_name = client_name if client_name.present? || integration.preferred_client_name.blank?
  integration.preferred_test_mode = test_mode if ENV['DELHIVERY_TEST_MODE'].present? || integration.preferred_test_mode.nil?
  integration.save!

  # 2. Delivery Profile & Origin Group
  profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery', store: store)
  origin_group = profile.delivery_origin_groups.first_or_create!

  # 3. Delivery Methods (Express & Surface)
  express = Spree::DeliveryMethod.find_or_initialize_by(name: 'Delhivery Express', delivery_profile: profile)
  if express.new_record?
    express.code = 'DELHIVERY_EXPRESS'
    express.admin_name = 'Delhivery Express'
    express.store = store
    express.delivery_origin_group = origin_group
    express.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    express.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    express.storefront_visible = true
    express.available_to_sellers = true
    express.save!
  end

  surface = Spree::DeliveryMethod.find_or_initialize_by(name: 'Delhivery Surface', delivery_profile: profile)
  if surface.new_record?
    surface.code = 'DELHIVERY_SURFACE'
    surface.admin_name = 'Delhivery Surface'
    surface.store = store
    surface.delivery_origin_group = origin_group
    surface.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    surface.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    surface.storefront_visible = true
    surface.available_to_sellers = true
    surface.save!
  end

  # 4. COD Payment Method
  cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
  if cod.new_record?
    cod.name = 'Cash on Delivery (Delhivery COD)'
    cod.active = true
    cod.storefront_visible = true
    cod.save!
  end

  puts "[SpreeDelhivery] ✓ Seeded Delhivery Integration, Profile, Express/Surface Methods, and COD for Store '#{store.name}'."
end
