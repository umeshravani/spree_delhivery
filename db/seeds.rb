# frozen_string_literal: true

ActiveRecord::Base.transaction do
  stores = Spree::Store.all.presence || [Spree::Store.default]

  api_token = ENV['DELHIVERY_API_TOKEN'].presence
  client_name = ENV['DELHIVERY_CLIENT_NAME'].presence || 'DelhiveryClient'
  test_mode = ENV['DELHIVERY_TEST_MODE'] == 'true' || (ENV['DELHIVERY_TEST_MODE'].nil? && true)

  stores.each do |store|
    next unless store

    # 1. Integration Record
    integration = store.integrations.find_or_initialize_by(type: 'SpreeDelhivery::Integration')
    integration.name = 'Delhivery' if integration.name.blank?

    if api_token.present?
      integration.preferred_api_token = api_token
    end

    if integration.preferred_client_name.blank?
      integration.preferred_client_name = client_name
    end

    if integration.preferred_test_mode.nil?
      integration.preferred_test_mode = test_mode
    end

    is_configured = integration.preferred_api_token.present?
    integration.active = is_configured
    integration.save!

    # 2. Single "Delhivery" Profile (Shipping, Default: true, All locations)
    delhivery_profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery', store: store) do |p|
      p.default = true
    end
    delhivery_profile.update!(default: true) unless delhivery_profile.default?

    origin_group = delhivery_profile.delivery_origin_groups.first_or_create!

    # 3. Delhivery Express Method (Inside single profile)
    express_method = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_EXPRESS', store: store)
    express_method.name = 'Delhivery Express'
    express_method.admin_name = 'Delhivery Express'
    express_method.delivery_profile = delhivery_profile
    express_method.delivery_origin_group = origin_group
    express_method.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    express_method.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    express_method.storefront_visible = is_configured if express_method.new_record?
    express_method.available_to_sellers = true
    express_method.save!

    # 4. Delhivery Surface Method (Inside single profile)
    surface_method = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_SURFACE', store: store)
    surface_method.name = 'Delhivery Surface'
    surface_method.admin_name = 'Delhivery Surface'
    surface_method.delivery_profile = delhivery_profile
    surface_method.delivery_origin_group = origin_group
    surface_method.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    surface_method.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    surface_method.storefront_visible = is_configured if surface_method.new_record?
    surface_method.available_to_sellers = true
    surface_method.save!

    # 5. Clean up any obsolete separate profiles
    Spree::DeliveryProfiles::Shipping.where(store: store, name: ['Delhivery Express', 'Delhivery Surface']).where.not(id: delhivery_profile.id).destroy_all

    # 6. COD Payment Method (Optional payment integration)
    cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
    if cod.new_record?
      cod.name = 'Cash on Delivery (Delhivery COD)'
      cod.active = is_configured
      cod.storefront_visible = is_configured
      cod.save!
    end

    puts "[SpreeDelhivery] ✓ Configured single 'Delhivery' profile with Express and Surface methods for Store '#{store.name}'."
  end
end
