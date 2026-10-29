# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'
require 'json'

# Load extension files
require_relative '../../app/services/spree_delhivery/client'
require_relative '../../app/models/spree_delhivery/measurement_converter'
require_relative '../../app/models/spree_delhivery/tracker_event'

module Spree
  class Integration
    def self.preference(name, type, options = {}); end
    def self.validates(*args); end
  end

  module DeliveryRateProvider
    class Base
      def current_integration(package); nil; end
    end
    class Estimate
      attr_reader :carrier, :service_level, :name, :cost, :currency, :metadata
      def initialize(attrs = {})
        attrs.each { |k, v| instance_variable_set("@#{k}", v) }
      end
    end
  end

  module FulfillmentProvider
    class Base; end
  end

  class LabelPurchase
    attr_reader :external_id, :carrier, :service, :tracking_number, :tracking_url, :cost, :currency, :format, :file_url, :metadata
    def initialize(attrs = {})
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
    end
  end

  module Core
    class LabelPurchaseRefused < StandardError; end
  end
end

require_relative '../../app/models/spree_delhivery/integration'
require_relative '../../app/models/spree_delhivery/delivery_rate_provider'
require_relative '../../app/models/spree_delhivery/fulfillment_provider'

RSpec.describe SpreeDelhivery do
  let(:client) { SpreeDelhivery::Client.new(api_token: 'test_token_123', test_mode: true) }

  describe SpreeDelhivery::Client do
    it 'initializes with staging URL in test mode' do
      expect(client.base_url).to eq(SpreeDelhivery::Client::STAGING_URL)
    end

    it 'initializes with live URL in production mode' do
      live_client = SpreeDelhivery::Client.new(api_token: 'prod_token', test_mode: false)
      expect(live_client.base_url).to eq(SpreeDelhivery::Client::LIVE_URL)
    end

    describe '#serviceability' do
      it 'checks pincode serviceability' do
        response_body = {
          'delivery_codes' => [
            { 'postal_code' => { 'pin' => 110001, 'pre_paid' => 'Y', 'cod' => 'Y' } }
          ]
        }.to_json

        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true, status: 200, body: response_body)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        expect(client.serviceability(pin: 110001)).to be true
        expect(client.cod_serviceable?(pin: 110001)).to be true
      end

      it 'returns false when pincode is unserviceable' do
        response_body = { 'delivery_codes' => [] }.to_json
        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true, status: 200, body: response_body)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        expect(client.serviceability(pin: 999999)).to be false
        expect(client.cod_serviceable?(pin: 999999)).to be false
      end
    end

    describe '#calculate_rate' do
      it 'returns dynamic quotation total from Kinko charges API' do
        response_body = [{ 'total_amount' => 145.50 }].to_json
        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true, status: 200, body: response_body)
        allow(fake_conn).to receive(:get).with('/api/kinko/v1/invoice/charges.json').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        rate = client.calculate_rate(
          origin_pin: 110001,
          destination_pin: 400001,
          weight_in_grams: 500,
          mode: 'E'
        )
        expect(rate).to eq(145.50)
      end
    end

    describe '#cancel_shipment' do
      it 'posts cancellation payload and returns boolean' do
        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true)
        allow(fake_conn).to receive(:post).with('/api/p/edit').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        expect(client.cancel_shipment(waybill: '1234567890')).to be true
      end
    end
  end

  describe SpreeDelhivery::TrackerEvent do
    it 'maps Delhivery tracking statuses to canonical Spree delivery statuses' do
      payload = {
        'Shipment' => {
          'AWB' => 'DELH12345678',
          'Status' => {
            'Status' => 'In Transit',
            'StatusLocation' => 'Mumbai Hub'
          }
        }
      }

      event = described_class.from_webhook(payload)
      args = event.to_update_tracking_arguments

      expect(args[:tracking_code]).to eq('DELH12345678')
      expect(args[:tracking_status]).to eq('in_transit')
      expect(args[:details]).to eq('Mumbai Hub')
      expect(args[:delivered_at]).to be_nil
    end

    it 'sets delivered_at when status is Delivered' do
      payload = {
        'Shipment' => {
          'AWB' => 'DELH12345678',
          'Status' => {
            'Status' => 'Delivered',
            'StatusLocation' => 'Delivered to recipient'
          }
        }
      }

      event = described_class.from_webhook(payload)
      args = event.to_update_tracking_arguments

      expect(args[:tracking_status]).to eq('delivered')
      expect(args[:delivered_at]).to be_present
    end
  end

  describe SpreeDelhivery::MeasurementConverter do
    it 'converts various weight units to grams accurately' do
      expect(described_class.to_grams(1, unit: 'kg')).to eq(1000.0)
      expect(described_class.to_grams(500, unit: 'g')).to eq(500.0)
      expect(described_class.to_grams(1, unit: 'lb')).to be_within(0.1).of(453.59)
    end

    it 'converts dimension units to centimeters accurately' do
      expect(described_class.to_centimeters(10, unit: 'cm')).to eq(10.0)
      expect(described_class.to_centimeters(100, unit: 'mm')).to eq(10.0)
      expect(described_class.to_centimeters(1, unit: 'in')).to eq(2.54)
    end
  end

  describe SpreeDelhivery::FulfillmentProvider do
    let(:provider) { described_class.new }

    it 'is idempotent and returns existing label without rebooking' do
      integration = double('Integration', client: client)
      allow(provider).to receive(:integration_for).and_return(integration)

      owner = double(
        'Fulfillment',
        is_a?: false,
        tracking_number: 'DELH_EXISTING_999',
        shipping_label: double('ShippingLabel', tracking_number: 'DELH_EXISTING_999'),
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 120.0),
        store: double('Store', default_currency: 'INR'),
        order: double('Order')
      )

      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_EXISTING_999').and_return('https://delhivery.com/label.pdf')
      expect(client).not_to receive(:create_shipment)

      label = provider.purchase_label(owner)
      expect(label.tracking_number).to eq('DELH_EXISTING_999')
      expect(label.file_url).to eq('https://delhivery.com/label.pdf')
    end
  end
end
