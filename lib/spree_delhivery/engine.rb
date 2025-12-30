# frozen_string_literal: true

module SpreeDelhivery
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_delhivery'

    # 1. Load Decorators
    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)

    # 2. OVERRIDE VIEWS
    initializer "spree_delhivery.views", before: :load_config_initializers do |app|
      app.config.paths["app/views"].unshift File.join(root, "app/views")
    end

    # 3. REGISTER INTEGRATION
    initializer "spree_delhivery.register.integrations" do |app|
      Rails.application.config.after_initialize do
        if Rails.application.config.respond_to?(:spree)
          Rails.application.config.spree.integrations << Spree::Integrations::Delhivery
        end
      end
    end

    # 4. REGISTER CALCULATOR
    config.after_initialize do |app|
      if app.config.spree.calculators.respond_to?(:shipping_methods)
        app.config.spree.calculators.shipping_methods << Spree::Calculator::Shipping::Delhivery
      end
    end
  end
end