# frozen_string_literal: true

require 'spec_helper'
require 'spree_delhivery'
require File.expand_path('../../../app/services/spree_delhivery/client', __dir__)
require File.expand_path('../../../app/models/spree_delhivery/tracker_event', __dir__)
require File.expand_path('../../../app/models/spree_delhivery/measurement_converter', __dir__)
module Spree
  class Return; end
  LabelPurchase = Struct.new(:external_id, :carrier, :service, :tracking_number, :tracking_url, :cost, :currency, :format, :file_url, :metadata, keyword_init: true)
  module FulfillmentProvider
    class Base
      def integration_for(target); end
    end
  end
  module Core
  end
end
Spree::Core::LabelPurchaseRefused ||= Class.new(StandardError)
require File.expand_path('../../../app/models/spree_delhivery/fulfillment_provider', __dir__)
require 'ostruct'
require 'json'

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
        fake_response = double('FaradayResponse', success?: true, status: 200)
        allow(fake_conn).to receive(:post).with('/api/p/edit').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        expect(client.cancel_shipment(waybill: '1234567890')).to be true
      end
    end

    describe '#find_shipment_by_ref' do
      it 'queries packages API with ref_ids and extracts active waybill' do
        response_body = {
          'ShipmentData' => [
            {
              'Shipment' => {
                'AWB' => 'DELH_REF_AWB_101',
                'RefNo' => 'ORD-12345',
                'Status' => { 'Status' => 'In Transit' }
              }
            }
          ]
        }.to_json

        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true, status: 200, body: response_body)
        allow(fake_conn).to receive(:get).with('/api/v1/packages/json/').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        result = client.find_shipment_by_ref(ref_id: 'ORD-12345')
        expect(result).not_to be_nil
        expect(result[:waybill]).to eq('DELH_REF_AWB_101')
        expect(result[:status]).to eq('In Transit')
      end

      it 'returns nil if shipment is cancelled or not found' do
        response_body = {
          'ShipmentData' => [
            {
              'Shipment' => {
                'AWB' => 'DELH_CANCELLED_AWB',
                'RefNo' => 'ORD-12345',
                'Status' => { 'Status' => 'Cancelled' }
              }
            }
          ]
        }.to_json

        fake_conn = double('FaradayConnection')
        fake_response = double('FaradayResponse', success?: true, status: 200, body: response_body)
        allow(fake_conn).to receive(:get).with('/api/v1/packages/json/').and_return(fake_response)
        allow(client).to receive(:connection).and_return(fake_conn)

        expect(client.find_shipment_by_ref(ref_id: 'ORD-12345')).to be_nil
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

    it 'rejects concurrent booking attempts when booking is already in progress' do
      integration = double('Integration', client: client)
      allow(provider).to receive(:integration_for).and_return(integration)

      owner = double(
        'Fulfillment',
        is_a?: false,
        id: 99,
        number: 'F99',
        tracking_number: nil,
        shipping_label: nil,
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 120.0),
        store: double('Store', default_currency: 'INR'),
        order: double('Order', number: 'R99999'),
        metadata: {
          'delhivery_booking_state' => 'in_progress',
          'delhivery_booking_started_at' => Time.current.iso8601
        },
        persisted?: false
      )

      expect {
        provider.purchase_label(owner)
      }.to raise_error(Spree::Core::LabelPurchaseRefused, /Delhivery shipment booking is currently in progress/)
    end

    it 'reconciles existing waybill from Delhivery without re-calling create_shipment on retry' do
      integration = double('Integration', client: client)
      allow(provider).to receive(:integration_for).and_return(integration)

      owner = double(
        'Fulfillment',
        is_a?: false,
        id: 100,
        number: 'F100',
        tracking_number: nil,
        shipping_label: nil,
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 120.0),
        store: double('Store', default_currency: 'INR'),
        order: double('Order', number: 'R10000'),
        metadata: {},
        persisted?: false
      )
      allow(owner).to receive(:metadata=)

      # Delhivery package lookup finds the existing waybill
      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R10000-F100').and_return({
        waybill: 'DELH_RECOVERED_100',
        ref_id: 'R10000-F100',
        status: 'Manifested'
      })
      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_RECOVERED_100').and_return('https://delhivery.com/recovered.pdf')

      # Must NOT call create_shipment!
      expect(client).not_to receive(:create_shipment)

      label = provider.purchase_label(owner)
      expect(label.tracking_number).to eq('DELH_RECOVERED_100')
      expect(label.file_url).to eq('https://delhivery.com/recovered.pdf')
    end

    it 'pauses automatic rebooking and flags requires_reconciliation when timeout occurs and carrier has not confirmed' do
      integration = double('Integration', client: client)
      allow(provider).to receive(:integration_for).and_return(integration)

      owner = double(
        'Fulfillment',
        is_a?: false,
        id: 102,
        number: 'F102',
        tracking_number: nil,
        shipping_label: nil,
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 120.0),
        store: double('Store', default_currency: 'INR'),
        order: double('Order', number: 'R10200'),
        metadata: { 'delhivery_booking_state' => 'requires_reconciliation' },
        persisted?: false
      )
      allow(owner).to receive(:metadata=)

      # Carrier tracking returns nil (unindexed or unbooked)
      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R10200-F102').and_return(nil)

      # Must NEVER call create_shipment blindly
      expect(client).not_to receive(:create_shipment)

      expect {
        provider.purchase_label(owner)
      }.to raise_error(Spree::Core::LabelPurchaseRefused, /Automatic rebooking is paused/)
    end

    it 'supports Spree 6 fulfillments without tracking_number method, ignores claimed blank labels, prefers master pickup location, resolves non-ASCII states, and handles Prepaid orders' do
      integration = double('Integration', client: client, preferred_pickup_location_name: 'Artolika HUB')
      allow(provider).to receive(:integration_for).and_return(integration)

      claimed_blank_label = double('ShippingLabel', status: 'purchased', tracking_number: nil)
      country_in = double('Country', iso: 'IN')
      dest_address = double(
        'Address',
        full_name: 'Umesh Ravani',
        company: nil,
        address1: '5-535-334',
        address2: 'Anant Vihar',
        postal_code: '505001',
        city: 'Karimnagar',
        state: nil,
        state_name: nil,
        state_code: 'TS',
        state_name_text: 'तेलंगाना',
        country: country_in,
        phone: '+91 9876543210'
      )
      stock_location = double(
        'StockLocation',
        name: 'Shop location',
        default?: true,
        seller_id: nil,
        phone: '09989147064',
        address1: '6-6-743/4/A',
        address2: 'Opp Adarsh Nagar Road',
        city: 'Karimnagar',
        zipcode: '505001',
        state: nil,
        state_name: nil,
        state_code: 'TS',
        company: 'Artolika.Inc'
      )
      variant = double('Variant', name: 'Handcrafted Wall Art', weight: 1.2, weight_unit: 'kg', dimensions_unit: 'cm', depth: 30, width: 20, height: 5)
      content_item = double('ContentItem', variant: variant, quantity: 1, price: 2900.0)
      package = double('Package', contents: [content_item], weight: nil)
      prepaid_method = double('PaymentMethod', type: 'SpreeRazorpay::Gateway')
      payment = double('Payment', payment_method: prepaid_method, status: 'completed', amount: 3047.97)
      order = double(
        'Order',
        number: 'R1002',
        total: 3047.97,
        currency: 'INR',
        completed_at: Time.utc(2026, 11, 10, 11, 50, 0),
        created_at: Time.utc(2026, 11, 10, 11, 45, 0),
        ship_address: dest_address,
        payments: [payment]
      )
      owner = double(
        'Spree::Fulfillment',
        id: 11,
        number: 'R1002-F1',
        shipping_labels: [claimed_blank_label],
        selected_delivery_rate: double('Rate', service_level: 'Surface', cost: 147.97),
        store: double('Store', name: 'TheWallX', default_currency: 'INR', default_weight_unit: 'kg'),
        order: order,
        address: dest_address,
        stock_location: stock_location,
        to_package: package,
        metadata: {},
        persisted?: false
      )
      allow(owner).to receive(:is_a?).with(Spree::Return).and_return(false)
      allow(owner).to receive(:metadata=)

      stub_const('ISO3166::Country', Class.new do
        def initialize(_iso); end

        def subdivisions
          {
            'TS' => Struct.new(:name, :translations).new('तेलंगाना', { en: 'Telangana' })
          }
        end
      end)

      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R1002-F1').and_return(nil)
      expect(client).not_to receive(:register_warehouse)
      expect(client).to receive(:create_shipment) do |payload:|
        shipment = payload[:shipments].first
        expect(payload[:pickup_location]).to eq({ name: 'Artolika HUB' })
        expect(shipment[:order]).to eq('R1002-F1')
        expect(shipment[:payment_mode]).to eq('Pre-paid')
        expect(shipment[:cod_amount]).to eq(0.0)
        expect(shipment[:shipping_mode]).to eq('Surface')
        expect(shipment[:state]).to eq('Telangana')
        expect(shipment[:return_state]).to eq('Telangana')
        expect(shipment[:phone]).to eq('9876543210')
        expect(shipment[:return_phone]).to eq('9989147064')
        { waybill: 'DELH_PREPAID_1002', upload_wbn: 'UPL1002', sort_code: 'HYD' }
      end
      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_PREPAID_1002').and_return('https://delhivery.com/r1002.pdf')

      label = provider.purchase_label(owner)
      expect(label.tracking_number).to eq('DELH_PREPAID_1002')
      expect(label.service).to eq('Surface')
      expect(provider.create_fulfillment(owner)).to eq({})
    end

    it 'calculates exact COD amount across split payments on DelhiveryCod orders' do
      integration = double('Integration', client: client, preferred_pickup_location_name: 'Artolika HUB')
      allow(provider).to receive(:integration_for).and_return(integration)

      dest_address = double(
        'Address',
        full_name: 'Buyer One',
        company: nil,
        address1: '12 Main St',
        address2: nil,
        postal_code: '110011',
        city: 'Delhi',
        state: nil,
        state_name: nil,
        state_code: 'DL',
        state_name_text: 'Delhi',
        country: double('Country', iso: 'IN'),
        phone: '9911223344'
      )
      stock_location = double(
        'StockLocation',
        name: 'Shop location',
        default?: true,
        seller_id: nil,
        phone: '9989147064',
        address1: 'Hub Road',
        address2: nil,
        city: 'Karimnagar',
        zipcode: '505001',
        state: nil,
        state_name: nil,
        state_code: 'TS',
        company: 'Artolika'
      )
      variant = double('Variant', name: 'Frame', weight: 0.8, weight_unit: 'kg', dimensions_unit: 'cm', depth: 25, width: 25, height: 4)
      package = double('Package', contents: [double('Item', variant: variant, quantity: 2, price: 2900.0)], weight: nil)
      cod_method = double('PaymentMethod', type: 'Spree::PaymentMethod::DelhiveryCod')
      credit_method = double('PaymentMethod', type: 'Spree::PaymentMethod::StoreCredit')
      payments = [
        double('Payment', payment_method: credit_method, status: 'completed', amount: 1000.0),
        double('Payment', payment_method: cod_method, status: 'pending', amount: 5162.76)
      ]
      order = double(
        'Order',
        number: 'R1001',
        total: 6162.76,
        currency: 'INR',
        completed_at: Time.utc(2026, 11, 10, 11, 48, 0),
        created_at: Time.utc(2026, 11, 10, 11, 40, 0),
        ship_address: dest_address,
        payments: payments
      )
      owner = double(
        'Spree::Fulfillment',
        id: 9,
        number: 'R1001-F1',
        shipping_labels: [],
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 263.76),
        store: double('Store', name: 'TheWallX', default_currency: 'INR', default_weight_unit: 'kg'),
        order: order,
        address: dest_address,
        stock_location: stock_location,
        to_package: package,
        metadata: {},
        persisted?: false
      )
      allow(owner).to receive(:is_a?).with(Spree::Return).and_return(false)
      allow(owner).to receive(:metadata=)

      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R1001-F1').and_return(nil)
      expect(client).to receive(:create_shipment) do |payload:|
        shipment = payload[:shipments].first
        expect(shipment[:payment_mode]).to eq('COD')
        expect(shipment[:cod_amount]).to eq(5162.76)
        expect(shipment[:total_amount]).to eq(6162.76)
        { waybill: 'DELH_COD_1001', upload_wbn: 'UPL1001', sort_code: 'DEL' }
      end
      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_COD_1001').and_return('https://delhivery.com/r1001.pdf')

      label = provider.purchase_label(owner)
      expect(label.tracking_number).to eq('DELH_COD_1001')
    end

    it 'supports Spree::Return reverse pickup labels without selected_delivery_rate' do
      integration = double('Integration', client: client, preferred_pickup_location_name: 'Artolika HUB')
      allow(provider).to receive(:integration_for).and_return(integration)

      ship_from = double(
        'Address',
        full_name: 'Customer Return',
        company: nil,
        address1: '10 Return St',
        address2: nil,
        postal_code: '400001',
        city: 'Mumbai',
        state: nil,
        state_name: 'Maharashtra',
        state_code: 'MH',
        state_name_text: 'Maharashtra',
        country: double('Country', iso: 'IN'),
        phone: '9820012345'
      )
      stock_location = double(
        'StockLocation',
        name: 'Shop location',
        default?: true,
        seller_id: nil,
        phone: '9989147064',
        address1: 'Hub Road',
        address2: nil,
        city: 'Karimnagar',
        zipcode: '505001',
        state: nil,
        state_name: nil,
        state_code: 'TS',
        company: 'Artolika'
      )
      variant = double('Variant', name: 'Art Print', weight: 0.5, weight_unit: 'kg', dimensions_unit: 'cm', depth: 20, width: 15, height: 3)
      package = double('Package', contents: [double('Item', variant: variant, quantity: 1, price: 1500.0)], weight: nil)
      order = double(
        'Order',
        number: 'R2001',
        total: 1500.0,
        currency: 'INR',
        completed_at: Time.utc(2026, 11, 10, 10, 0, 0),
        created_at: Time.utc(2026, 11, 10, 9, 50, 0),
        ship_address: ship_from,
        payments: []
      )
      owner = double(
        'Spree::Return',
        id: 50,
        number: 'RET2001',
        shipping_labels: [],
        store: double('Store', name: 'TheWallX', default_currency: 'INR', default_weight_unit: 'kg'),
        order: order,
        ship_from_address: ship_from,
        stock_location: stock_location,
        to_package: package,
        metadata: {},
        persisted?: false
      )
      allow(owner).to receive(:is_a?).with(Spree::Return).and_return(true)
      allow(owner).to receive(:metadata=)

      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R2001-RET2001').and_return(nil)
      expect(client).to receive(:create_shipment) do |payload:|
        shipment = payload[:shipments].first
        expect(shipment[:payment_mode]).to eq('Pickup')
        expect(shipment[:cod_amount]).to eq(0.0)
        expect(shipment[:shipping_mode]).to eq('Express')
        { waybill: 'DELH_RET_2001', upload_wbn: 'UPL_RET', sort_code: 'BOM' }
      end
      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_RET_2001').and_return('https://delhivery.com/ret2001.pdf')

      label = provider.purchase_label(owner)
      expect(label.tracking_number).to eq('DELH_RET_2001')
    end

    it 'retries shipment creation with preferred_pickup_location_name when non-default warehouse is rejected' do
      integration = double('Integration', client: client, preferred_pickup_location_name: 'Artolika HUB')
      allow(provider).to receive(:integration_for).and_return(integration)

      dest_address = double(
        'Address',
        full_name: 'Customer',
        company: nil,
        address1: '100 Market Rd',
        address2: nil,
        postal_code: '560001',
        city: 'Bengaluru',
        state: nil,
        state_name: 'Karnataka',
        state_code: 'KA',
        state_name_text: 'Karnataka',
        country: double('Country', iso: 'IN'),
        phone: '9880011223'
      )
      stock_location = double(
        'StockLocation',
        name: 'Secondary Warehouse',
        default?: false,
        seller_id: nil,
        phone: '9989147064',
        address1: '200 Depot',
        address2: nil,
        city: 'Hyderabad',
        zipcode: '500001',
        state: nil,
        state_name: 'Telangana',
        state_code: 'TS',
        company: 'Artolika'
      )
      variant = double('Variant', name: 'Print', weight: 0.5, weight_unit: 'kg', dimensions_unit: 'cm', depth: 10, width: 10, height: 10)
      package = double('Package', contents: [double('Item', variant: variant, quantity: 1, price: 1000.0)], weight: nil)
      order = double('Order', number: 'R3001', total: 1000.0, currency: 'INR', completed_at: Time.utc(2026, 11, 10), created_at: Time.utc(2026, 11, 10), ship_address: dest_address, payments: [])
      owner = double(
        'Spree::Fulfillment',
        id: 77,
        number: 'R3001-F1',
        shipping_labels: [],
        selected_delivery_rate: double('Rate', service_level: 'Express', cost: 100.0),
        store: double('Store', name: 'TheWallX', default_currency: 'INR', default_weight_unit: 'kg'),
        order: order,
        address: dest_address,
        stock_location: stock_location,
        to_package: package,
        metadata: {},
        persisted?: false
      )
      allow(owner).to receive(:is_a?).with(Spree::Return).and_return(false)
      allow(owner).to receive(:metadata=)

      allow(client).to receive(:find_shipment_by_ref).with(ref_id: 'R3001-F1').and_return(nil)
      allow(client).to receive(:register_warehouse).and_return(false)
      calls = []
      allow(client).to receive(:create_shipment) do |payload:|
        calls << payload[:pickup_location][:name]
        if calls.size == 1
          raise Spree::Core::LabelPurchaseRefused, 'Delhivery rejected shipment: ClientWarehouse matching query does not exist'
        end

        { waybill: 'DELH_FALLBACK_3001', upload_wbn: 'UPL3001', sort_code: 'BLR' }
      end
      allow(client).to receive(:fetch_packing_slip_url).with(waybill: 'DELH_FALLBACK_3001').and_return('https://delhivery.com/r3001.pdf')

      stub_const('Rails', double('Rails', logger: double('Logger', warn: nil, error: nil)))
      label = provider.purchase_label(owner)
      expect(calls).to eq(['Secondary Warehouse', 'Artolika HUB'])
      expect(label.tracking_number).to eq('DELH_FALLBACK_3001')
    end

    it 'cancels waybill and clears metadata on refund_label and cancel_fulfillment' do
      integration = double('Integration', client: client)
      meta = { 'delhivery_waybill' => 'DELH_CANCEL_1', 'other' => 'keep' }
      owner = double('Spree::Fulfillment', shipping_labels: [], metadata: meta, persisted?: false)
      allow(owner).to receive(:metadata=) { |m| meta.replace(m) }
      allow(provider).to receive(:integration_for).with(owner).and_return(integration)

      shipping_label = double('ShippingLabel', integration: integration, owner: owner, tracking_number: 'DELH_CANCEL_1')
      expect(client).to receive(:cancel_shipment).with(waybill: 'DELH_CANCEL_1').and_return(true)

      expect(provider.refund_label(shipping_label)).to eq('refunded')
      expect(meta).to eq({ 'other' => 'keep' })
      expect(provider.cancel_fulfillment(owner)).to be true
    end
  end
end
