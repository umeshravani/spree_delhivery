# frozen_string_literal: true

store = Spree::Store.default

# 1. Delivery Profile & Origin Group
profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery', store: store)
origin_group = profile.delivery_origin_groups.first_or_create!

# 2. Delivery Methods (Express & Surface)
Spree::DeliveryMethod.find_or_create_by!(name: 'Delhivery Express', delivery_profile: profile) do |dm|
  dm.code = 'DELHIVERY_EXPRESS'
  dm.admin_name = 'Delhivery Express'
  dm.store = store
  dm.delivery_origin_group = origin_group
  dm.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
  dm.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
  dm.storefront_visible = true
  dm.available_to_sellers = true
end

Spree::DeliveryMethod.find_or_create_by!(name: 'Delhivery Surface', delivery_profile: profile) do |dm|
  dm.code = 'DELHIVERY_SURFACE'
  dm.admin_name = 'Delhivery Surface'
  dm.store = store
  dm.delivery_origin_group = origin_group
  dm.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
  dm.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
  dm.storefront_visible = true
  dm.available_to_sellers = true
end

# 3. COD Payment Method
Spree::PaymentMethod::DelhiveryCod.find_or_create_by!(type: 'Spree::PaymentMethod::DelhiveryCod', store: store) do |pm|
  pm.name = 'Cash on Delivery (Delhivery COD)'
  pm.active = true
  pm.storefront_visible = true
end

puts '[SpreeDelhivery] Successfully seeded Delhivery Delivery Profile, Express & Surface Methods, and COD Payment Method!'
