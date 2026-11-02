# frozen_string_literal: true

require 'rails/generators'

module SpreeDelhivery
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc 'Installs Spree Delhivery and configures Delhivery Surface and Express shipping profiles in Spree'

      source_root File.expand_path('templates', __dir__)

      class_option :api_token, type: :string, desc: 'Delhivery API Token'
      class_option :client_name, type: :string, default: 'DelhiveryClient', desc: 'Delhivery Registered Client Name'
      class_option :pickup_location, type: :string, desc: 'Registered Delhivery Pickup Location Name'
      class_option :cod_surcharge, type: :numeric, default: 0.0, desc: 'Default Cash on Delivery Surcharge (INR)'
      class_option :auto_run_seeds, type: :boolean, default: true, desc: 'Auto-seed delivery profiles, methods, and COD'

      def run_seeds
        if options[:auto_run_seeds]
          say_status :configuring, 'Configuring Delhivery Surface & Express Delivery Profiles...', :green
          ENV['DELHIVERY_API_TOKEN'] = options[:api_token] if options[:api_token].present?
          ENV['DELHIVERY_CLIENT_NAME'] = options[:client_name] if options[:client_name].present?
          ENV['DELHIVERY_PICKUP_LOCATION_NAME'] = options[:pickup_location] if options[:pickup_location].present?
          ENV['DELHIVERY_COD_SURCHARGE'] = options[:cod_surcharge].to_s if options[:cod_surcharge].present?

          seed_file = File.expand_path('../../../../db/seeds.rb', __dir__)
          load(seed_file) if File.exist?(seed_file)
        else
          say_status :skipped, 'Skipping default profile configuration. Run `bin/rails g spree_delhivery:install` anytime.', :yellow
        end
      end
    end
  end
end
