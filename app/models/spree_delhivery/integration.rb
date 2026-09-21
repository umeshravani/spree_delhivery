# frozen_string_literal: true

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

    def self.integration_group
      'shipping'
    end

    def self.integration_name
      'Delhivery'
    end

    def self.logo_url
      DELHIVERY_DATA_URI
    end

    def self.description
      'Express parcel delivery, automated AWB generation, and real-time tracking across India.'
    end

    def can_connect?
      return false if preferred_api_token.blank?
      return true if Rails.env.development? || preferred_test_mode? || preferred_api_token.to_s.start_with?('test')

      client.check_pincode(store.default_stock_location&.zipcode || '110001')
      true
    rescue StandardError => e
      self.connection_error_message = e.message
      false
    end

    def parse_webhook_event(raw_post, _headers)
      payload = JSON.parse(raw_post)
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
