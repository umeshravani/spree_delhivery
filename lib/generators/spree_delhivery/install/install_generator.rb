module SpreeDelhivery
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      class_option :auto_run_migrations, type: :boolean, default: false

      def add_migrations
        run 'bundle exec rake railties:install:migrations FROM=spree_delhivery'
      end

      def run_migrations
        run_migrations = options[:auto_run_migrations] || ['', 'y', 'Y'].include?(ask('Would you like to run the migrations now? [Y/n]'))
        if run_migrations
          run 'bundle exec rake db:migrate'
        else
          puts 'Skipping rake db:migrate, don\'t forget to run it!'
        end
      end

      def seed_shipping_methods
        if yes?("Would you like to create 'Delhivery Surface' and 'Express' shipping methods now? [Y/n]")
          
          # Ensure Calculator class is loaded
          begin
            require 'spree/calculator/shipping/delhivery'
          rescue LoadError
            if defined?(Spree::Calculator::Shipping::Delhivery)
               # Already loaded
            else
               puts "⚠️ Warning: Could not load Calculator class. Skipping seeding."
               return
            end
          end

          calc_class = Spree::Calculator::Shipping::Delhivery

          # 1. Create Surface
          surface = Spree::ShippingMethod.find_or_create_by!(name: "Delhivery Surface") do |sm|
            sm.calculator = calc_class.new
            sm.calculator.preferred_service_mode = 'Surface' # Full Name
            sm.calculator.preferred_handling_fee = 0
            sm.display_on = 'both'
            sm.code = 'DELHIVERY_S'
            sm.tracking_url = "https://www.delhivery.com/track/package/:tracking"
            
            category = Spree::ShippingCategory.first
            zone = Spree::Zone.first
            sm.shipping_categories << category if category
            sm.zones << zone if zone
          end
          # Enforce preference update
          surface.calculator.preferred_service_mode = 'Surface'
          surface.calculator.save
          puts "✅ Created/Updated 'Delhivery Surface'"

          # 2. Create Express
          express = Spree::ShippingMethod.find_or_create_by!(name: "Delhivery Express") do |sm|
            sm.calculator = calc_class.new
            sm.calculator.preferred_service_mode = 'Express' # Full Name
            sm.calculator.preferred_handling_fee = 0
            sm.display_on = 'both'
            sm.code = 'DELHIVERY_E'
            sm.tracking_url = "https://www.delhivery.com/track/package/:tracking"
            
            category = Spree::ShippingCategory.first
            zone = Spree::Zone.first
            sm.shipping_categories << category if category
            sm.zones << zone if zone
          end
          # Enforce preference update
          express.calculator.preferred_service_mode = 'Express'
          express.calculator.save
          puts "✅ Created/Updated 'Delhivery Express'"
          
        else
          puts "Skipping Shipping Method creation."
        end
      rescue StandardError => e
        puts "⚠️ Could not seed shipping methods: #{e.message}"
        puts "Please ensure Spree is installed and the database is migrated."
      end
    end
  end
end