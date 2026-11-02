# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Api::V3::Store::DelhiveryController, type: :controller do
  render_views
  routes { Spree::Core::Engine.routes }
  include_context 'API v3 Store guest'

  before do
    request.headers.merge!(headers)
  end

  let!(:integration) do
    SpreeDelhivery::Integration.create!(
      store: store,
      preferred_api_token: 'valid_test_token_123',
      preferred_client_name: 'TEST_CLIENT',
      preferred_test_mode: true,
      active: true
    )
  end

  let(:fake_conn) { instance_double(Faraday::Connection) }

  describe 'GET #serviceability' do
    context 'with invalid PIN code format' do
      it 'returns 400 Bad Request for short PIN code' do
        get :serviceability, params: { pincode: '123' }, as: :json

        expect(response).to have_http_status(:bad_request)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['message']).to include('valid 6-digit Indian PIN code')
      end

      it 'returns 400 Bad Request for non-numeric PIN code' do
        get :serviceability, params: { pincode: 'abcdef' }, as: :json

        expect(response).to have_http_status(:bad_request)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
      end
    end

    context 'with unserviceable PIN code (e.g., 222222)' do
      it 'fails closed and reports unserviceable when carrier returns empty delivery codes' do
        fake_res = instance_double(
          Faraday::Response,
          success?: true,
          status: 200,
          body: { delivery_codes: [] }.to_json
        )
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_res)

        get :serviceability, params: { pincode: '222222' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['pincode']).to eq('222222')
        expect(data['message']).to eq('Delivery is currently unavailable to this PIN code.')
      end

      it 'reports unserviceable when both prepaid and cod are disabled' do
        body_data = {
          delivery_codes: [
            {
              postal_code: {
                pin: 222222,
                city: 'Remote S.O',
                district: 'Remote District',
                state_code: 'UP',
                pre_paid: 'N',
                cod: 'N',
                cash: 'N'
              }
            }
          ]
        }.to_json

        fake_res = instance_double(Faraday::Response, success?: true, status: 200, body: body_data)
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_res)

        get :serviceability, params: { pincode: '222222' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['cod_available']).to be false
        expect(data['prepaid_available']).to be false
        expect(data['message']).to eq('PIN code is currently unserviceable.')
      end
    end

    context 'with serviceable PIN code (e.g., 400001)' do
      it 'returns verified location, COD/prepaid availability, and verified ETA' do
        body_data = {
          delivery_codes: [
            {
              postal_code: {
                pin: 400001,
                city: 'Mumbai S.O',
                district: 'Mumbai District',
                state_code: 'MH',
                pre_paid: 'Y',
                cod: 'Y',
                expected_tat: 3
              }
            }
          ]
        }.to_json

        fake_res = instance_double(Faraday::Response, success?: true, status: 200, body: body_data)
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_res)

        get :serviceability, params: { pincode: '400001' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be true
        expect(data['pincode']).to eq('400001')
        expect(data['city']).to eq('Mumbai')
        expect(data['district']).to eq('Mumbai')
        expect(data['state']).to eq('Maharashtra')
        expect(data['state_code']).to eq('MH')
        expect(data['location']).to eq('Mumbai, Maharashtra')
        expect(data['cod_available']).to be true
        expect(data['prepaid_available']).to be true
        expect(data['estimated_days']).to eq('3 business days')
      end

      it 'does not fabricate estimated days when carrier does not provide verified TAT' do
        body_data = {
          delivery_codes: [
            {
              postal_code: {
                pin: 400001,
                city: 'Mumbai S.O',
                district: 'Mumbai District',
                state_code: 'MH',
                pre_paid: 'Y',
                cod: 'N'
              }
            }
          ]
        }.to_json

        fake_res = instance_double(Faraday::Response, success?: true, status: 200, body: body_data)
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_res)

        get :serviceability, params: { pincode: '400001' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be true
        expect(data['cod_available']).to be false
        expect(data['prepaid_available']).to be true
        expect(data['estimated_days']).to be_nil
      end
    end

    context 'when carrier is unavailable or times out' do
      it 'fails closed on timeout without fabricating serviceability' do
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_raise(Faraday::TimeoutError.new('Execution expired'))

        get :serviceability, params: { pincode: '400001' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['message']).to eq('Delivery serviceability check unavailable.')
      end

      it 'fails closed on carrier 500 error' do
        fake_res = instance_double(Faraday::Response, success?: false, status: 500, body: 'Internal Error')
        allow(Faraday).to receive(:new).and_return(fake_conn)
        allow(fake_conn).to receive(:get).with('/c/api/pin-codes/json/').and_return(fake_res)

        get :serviceability, params: { pincode: '400001' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['message']).to eq('Delivery serviceability check unavailable.')
      end
    end

    context 'when carrier credentials are missing' do
      it 'fails closed when integration is inactive and ENV is not set' do
        integration.update!(active: false)
        stub_const('ENV', ENV.to_h.merge('DELHIVERY_API_TOKEN' => nil))

        get :serviceability, params: { pincode: '400001' }, as: :json

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data['serviceable']).to be false
        expect(data['message']).to eq('Delivery serviceability check unavailable.')
      end
    end
  end
end
