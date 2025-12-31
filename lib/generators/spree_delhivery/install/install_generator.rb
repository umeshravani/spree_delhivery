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
          say_status :skipped, "Skipping rails db:migrate, don't forget to run it!", :yellow
        end
      end

      def seed_shipping_methods
        unless run_seeding?("Delhivery Surface and Express shipping methods")
          say_status :skipped, "Skipping Shipping Method creation.", :yellow
          return
        end

        # Safety Check: Ensure tables exist (in case user skipped migrations)
        unless Spree::ShippingMethod.table_exists? && Spree::Calculator.table_exists?
          say_status :error, "Database tables missing. Run migrations first.", :red
          return
        end

        # Ensure Calculator class is available
        unless calculator_class_available?
          say_status :error, "Spree::Calculator::Shipping::Delhivery not found. Restart server/console.", :red
          return
        end

        # Locate dependencies (Zones/Categories)
        shipping_category = Spree::ShippingCategory.find_by(name: 'Default') || Spree::ShippingCategory.first
        shipping_zone     = Spree::Zone.find_by(name: 'India') || Spree::Zone.first

        if shipping_category.nil? || shipping_zone.nil?
          say_status :warning, "Could not find a Shipping Category or Zone. Created methods will need manual setup.", :yellow
        end

        # Create Methods using Helper
        create_delhivery_method("Delhivery Surface", "DELHIVERY_S", "Surface", shipping_category, shipping_zone)
        create_delhivery_method("Delhivery Express", "DELHIVERY_E", "Express", shipping_category, shipping_zone)
      rescue StandardError => e
        say_status :error, "Could not seed shipping methods: #{e.message}", :red
      end

      def configure_cms_blocks
        # We don't ask for permission here, we just do it if the table exists, 
        # as it's a non-destructive UI enhancement.
        
        unless Spree::PageSection.table_exists?
          say_status :skipped, "Spree::PageSection table not found. Skipping CMS config.", :yellow
          return
        end

        say_status :configuring, "Checking Product Page Sections for Delhivery Widget..."
        
        count = 0
        Spree::PageSection.where(type: "Spree::PageSections::ProductDetails").find_each do |section|
          next if section.blocks.where(type: "Spree::PageBlocks::Products::DelhiveryEdd").exists?

          section.blocks.create!(
            type: "Spree::PageBlocks::Products::DelhiveryEdd",
            position: (section.blocks.maximum(:position) || 0).to_i + 1
          )
          count += 1
          say_status :added, "Delhivery Widget to '#{section.name}'", :green
        end
        
        if count > 0
          say_status :complete, "Added Delhivery Widget to #{count} sections.", :green
        else
          say_status :complete, "CMS Blocks already configured.", :blue
        end
      rescue StandardError => e
        say_status :error, "Could not configure CMS blocks: #{e.message}", :red
      end

      private

      # Helper to check if user wants to run a step
      def run_seeding?(feature_name)
        options[:auto_run_migrations] || ['', 'y', 'Y'].include?(ask("Would you like to create #{feature_name} now? [Y/n]"))
      end

      # Helper to check for the calculator class safely
      def calculator_class_available?
        return true if defined?(Spree::Calculator::Shipping::Delhivery)
        begin
          require 'spree/calculator/shipping/delhivery'
          true
        rescue LoadError
          false
        end
      end

      # DRY Helper to create shipping methods
      def create_delhivery_method(name, code, service_mode, category, zone)
        method = Spree::ShippingMethod.where(name: name).first_or_initialize
        
        is_new = method.new_record?
        method.code = code
        method.display_on = 'both'
        method.tracking_url = "https://www.delhivery.com/track/package/:tracking"
        
        # assign dependencies if they exist and aren't already assigned
        method.shipping_categories << category if category && !method.shipping_categories.include?(category)
        method.zones << zone if zone && !method.zones.include?(zone)

        # Calculator Setup
        if method.calculator.nil? || method.calculator.class != Spree::Calculator::Shipping::Delhivery
          method.calculator = Spree::Calculator::Shipping::Delhivery.new
        end
        
        # Set Preferences
        method.calculator.preferences = {
          service_mode: service_mode,
          handling_fee: 0
        }
        
        if method.save
          # Force save calculator to ensure preferences persist
          method.calculator.save! 
          say_status (is_new ? :created : :updated), name, :green
        else
          say_status :error, "Failed to save #{name}: #{method.errors.full_messages.join(', ')}", :red
        end
      end

    end
  end
end
