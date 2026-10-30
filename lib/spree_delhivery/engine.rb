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

    config.generators do |g|
      g.test_framework :rspec
    end

    config.to_prepare do
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        load(c)
      end
    end

    config.after_initialize do
      Spree.integrations << 'SpreeDelhivery::Integration'
      Spree.delivery_rate_providers << SpreeDelhivery::DeliveryRateProvider
      Spree.fulfillment_providers << SpreeDelhivery::FulfillmentProvider
      Rails.application.config.spree.payment_methods << Spree::PaymentMethod::DelhiveryCod
      
      require_relative '../../app/models/spree/adjusters/delhivery_cod_fee'
      if Rails.application.config.spree.respond_to?(:adjusters) && Rails.application.config.spree.adjusters
        unless Rails.application.config.spree.adjusters.include?(Spree::Adjusters::DelhiveryCodFee)
          Rails.application.config.spree.adjusters << Spree::Adjusters::DelhiveryCodFee
        end
      end
    end
  end
end
