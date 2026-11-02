# frozen_string_literal: true

ActiveRecord::Base.transaction do
  stores = Spree::Store.all.presence || [Spree::Store.default]

  api_token = ENV['DELHIVERY_API_TOKEN'].presence
  client_name = ENV['DELHIVERY_CLIENT_NAME'].presence || 'DelhiveryClient'
  test_mode = ENV['DELHIVERY_TEST_MODE'] == 'true' || (ENV['DELHIVERY_TEST_MODE'].nil? && true)

  stores.each do |store|
    next unless store

    # 1. Integration Record (Preserves existing merchant configuration)
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

    # Keep API credentials out of source code. Active only when token configured.
    is_configured = integration.preferred_api_token.present?
    integration.active = is_configured
    integration.save!

    # 2. Delhivery Surface Profile & Method
    surface_profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery Surface', store: store)
    surface_origin_group = surface_profile.delivery_origin_groups.first_or_create!

    surface_method = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_SURFACE', store: store)
    surface_method.name = 'Delhivery Surface' if surface_method.name.blank?
    surface_method.admin_name = 'Delhivery Surface' if surface_method.admin_name.blank?
    surface_method.delivery_profile = surface_profile
    surface_method.delivery_origin_group = surface_origin_group
    surface_method.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    surface_method.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    # Enabled only when properly configured
    surface_method.storefront_visible = is_configured if surface_method.new_record?
    surface_method.available_to_sellers = true
    surface_method.save!

    # 3. Delhivery Express Profile & Method
    express_profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery Express', store: store)
    express_origin_group = express_profile.delivery_origin_groups.first_or_create!

    express_method = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_EXPRESS', store: store)
    express_method.name = 'Delhivery Express' if express_method.name.blank?
    express_method.admin_name = 'Delhivery Express' if express_method.admin_name.blank?
    express_method.delivery_profile = express_profile
    express_method.delivery_origin_group = express_origin_group
    express_method.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
    express_method.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
    # Enabled only when properly configured
    express_method.storefront_visible = is_configured if express_method.new_record?
    express_method.available_to_sellers = true
    express_method.save!

    # 4. COD Payment Method (Optional payment integration)
    cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
    if cod.new_record?
      cod.name = 'Cash on Delivery (Delhivery COD)'
      cod.active = is_configured
      cod.storefront_visible = is_configured
      cod.save!
    end

    puts "[SpreeDelhivery] ✓ Configured Delhivery Surface & Express Profiles for Store '#{store.name}' (configured: #{is_configured})."
  end
end
