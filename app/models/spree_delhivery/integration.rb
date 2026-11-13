# frozen_string_literal: true

require 'base64'

module SpreeDelhivery
  class Integration < Spree::Integration
    DELHIVERY_LOGO_PATH = File.join(__dir__, '..', '..', 'assets', 'images', 'spree_delhivery', 'delhivery-icon.png')
    DELHIVERY_DATA_URI = "data:image/png;base64,#{Base64.strict_encode64(File.read(DELHIVERY_LOGO_PATH))}".freeze

    preference :api_token, :password
    preference :client_name, :string
    preference :pickup_location_name, :string
    preference :seller_gst_tin, :string
    preference :cod_surcharge, :decimal, default: 0.0
    preference :test_mode, :boolean, default: false

    validates :preferred_api_token, :preferred_client_name, presence: true

    after_save :ensure_delivery_profile_and_methods!, if: -> { active? }

    def self.integration_group
      'shipping'
    end

    def self.integration_name
      'Delhivery'
    end

    def self.logo_url
      DELHIVERY_DATA_URI
    end

    def self.docs_url
      'https://github.com/umeshravani/spree_delhivery/blob/spree-6/README.md'
    end

    def self.description
      'Express parcel delivery, automated AWB generation, and real-time tracking across India.'
    end

    def preferred_test_mode?
      preferred_test_mode
    end

    def can_connect?
      return false if preferred_api_token.blank?
      return true if Rails.env.development? || Rails.env.test? || preferred_test_mode? || preferred_api_token.to_s.start_with?('test')

      client.check_pincode(store&.default_stock_location&.zipcode || '110001')
      true
    rescue StandardError => e
      self.connection_error_message = e.message
      false
    end

    def ensure_delivery_profile_and_methods!
      return unless store

      # Find or create single 'Delhivery' profile
      profile = Spree::DeliveryProfiles::Shipping.find_or_create_by!(name: 'Delhivery', store: store) do |p|
        p.default = true
      end
      profile.update!(default: true) unless profile.default?

      origin_group = profile.delivery_origin_groups.first_or_create!

      # 1. Delhivery Surface Method
      surface = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_SURFACE', store: store)
      surface.name = 'Delhivery Surface' if surface.name.blank?
      surface.admin_name = 'Delhivery Surface' if surface.admin_name.blank?
      surface.delivery_profile = profile
      surface.delivery_origin_group = origin_group
      surface.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
      surface.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
      surface.available_to_sellers = true
      surface.storefront_visible = true
      surface.save!

      if surface.respond_to?(:services)
        surface_svc = surface.services.find_or_initialize_by(carrier: 'Delhivery', service: 'Surface')
        surface_svc.label = 'Delhivery Surface'
        surface_svc.position = 1
        surface_svc.save!
      end

      # 2. Delhivery Express Method
      express = Spree::DeliveryMethod.find_or_initialize_by(code: 'DELHIVERY_EXPRESS', store: store)
      express.name = 'Delhivery Express' if express.name.blank?
      express.admin_name = 'Delhivery Express' if express.admin_name.blank?
      express.delivery_profile = profile
      express.delivery_origin_group = origin_group
      express.rate_provider = 'SpreeDelhivery::DeliveryRateProvider'
      express.fulfillment_provider = 'SpreeDelhivery::FulfillmentProvider'
      express.available_to_sellers = true
      express.storefront_visible = true
      express.save!

      if express.respond_to?(:services)
        express_svc = express.services.find_or_initialize_by(carrier: 'Delhivery', service: 'Express')
        express_svc.label = 'Delhivery Express (Air)'
        express_svc.position = 1
        express_svc.save!
      end

      # 3. Ensure Delhivery COD Payment Method
      cod = Spree::PaymentMethod::DelhiveryCod.find_or_initialize_by(type: 'Spree::PaymentMethod::DelhiveryCod', store: store)
      cod.name = 'Cash on Delivery (Delhivery COD)' if cod.name.blank?
      cod.active = true
      cod.storefront_visible = true
      cod.save!

      # Remove obsolete separate profiles if they exist
      Spree::DeliveryProfiles::Shipping.where(store: store, name: ['Delhivery Express', 'Delhivery Surface']).where.not(id: profile.id).destroy_all
      profile
    rescue StandardError => e
      Rails.logger.warn("[SpreeDelhivery] Error ensuring delivery profile/methods: #{e.message}")
      raise e
    end

    def webhook_url
      return nil unless store
      base = store.formatted_url.presence || store.url_or_custom_domain.presence || "https://#{store.url}"
      "#{base.chomp('/')}/api/v3/webhooks/fulfillments/#{prefixed_id}"
    end

    def parse_webhook_event(raw_post, _headers)
      payload = JSON.parse(raw_post.to_s)
      SpreeDelhivery::TrackerEvent.from_webhook(payload)&.to_update_tracking_arguments
    rescue JSON::ParserError
      nil
    end

    def client
      @client ||= SpreeDelhivery::Client.new(
        api_token: preferred_api_token,
        client_name: preferred_client_name,
        test_mode: preferred_test_mode
      )
    end
  end
end
