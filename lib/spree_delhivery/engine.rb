# frozen_string_literal: true

require 'rails/engine'

module SpreeDelhivery
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_delhivery'

    initializer 'spree_delhivery.inflections', before: :set_autoload_paths do
      Rails.autoloaders.each do |autoloader|
        autoloader.inflector.inflect('spree_delhivery' => 'SpreeDelhivery')
      end
    end

    initializer 'spree_delhivery.append_migrations' do |app|
      unless app.root.to_s.match?(root.to_s)
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
        end
      end
    end

    config.generators do |g|
      g.test_framework :rspec
    end

    config.to_prepare do
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        load(c)
      end
    end

    config.after_initialize do
      Spree.integrations << 'SpreeDelhivery::Integration' unless Spree.integrations.include?('SpreeDelhivery::Integration')
      Spree.delivery_rate_providers << SpreeDelhivery::DeliveryRateProvider unless Spree.delivery_rate_providers.include?(SpreeDelhivery::DeliveryRateProvider)
      Spree.fulfillment_providers << SpreeDelhivery::FulfillmentProvider unless Spree.fulfillment_providers.include?(SpreeDelhivery::FulfillmentProvider)

      if Rails.application.config.respond_to?(:spree) && Rails.application.config.spree.respond_to?(:payment_methods)
        payment_methods_registry = Rails.application.config.spree.payment_methods
        payment_methods_registry << Spree::PaymentMethod::DelhiveryCod unless payment_methods_registry.include?(Spree::PaymentMethod::DelhiveryCod)
      end

      require_relative '../../app/models/spree/adjusters/delhivery_cod_fee'
      if defined?(Spree.adjusters) && Spree.adjusters
        Spree.adjusters << Spree::Adjusters::DelhiveryCodFee unless Spree.adjusters.include?(Spree::Adjusters::DelhiveryCodFee)
      end
      if Rails.application.config.respond_to?(:spree) && Rails.application.config.spree.respond_to?(:adjusters) && Rails.application.config.spree.adjusters
        adjusters_registry = Rails.application.config.spree.adjusters
        adjusters_registry << Spree::Adjusters::DelhiveryCodFee unless adjusters_registry.include?(Spree::Adjusters::DelhiveryCodFee)
      end

      # Runtime guard: ensure Delhivery COD payment method is available and active on every store
      begin
        if ActiveRecord::Base.connection.table_exists?('spree_payment_methods') && ActiveRecord::Base.connection.table_exists?('spree_stores')
          Spree::Store.all.each do |store|
            cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
            if cod.new_record?
              cod.name = 'Cash on Delivery (Delhivery COD)'
              cod.active = true
              cod.storefront_visible = true
              cod.save!
            elsif !cod.active? || !cod.storefront_visible?
              cod.update_columns(active: true, storefront_visible: true)
            end
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[SpreeDelhivery] Error ensuring COD payment method: #{e.message}")
      end
    end
  end
end
