# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Admin
        class DelhiveryController < Spree::Api::V3::Admin::BaseController
          def metadata
            token = params[:api_token].presence || integration&.preferred_api_token
            test_mode = if params[:test_mode].present?
                          ActiveModel::Type::Boolean.new.cast(params[:test_mode])
                        else
                          integration&.preferred_test_mode? || false
                        end

            if token.blank?
              return render json: {
                connected: false,
                clients: [],
                pickup_locations: [],
                has_delhivery_profile: has_delhivery_profile?
              }
            end

            client = SpreeDelhivery::Client.new(api_token: token, test_mode: test_mode)
            connected = client.check_pincode(current_store.default_stock_location&.zipcode || '110001')

            pickup_locations = client.fetch_pickup_locations
            clients = client.fetch_clients

            render json: {
              connected: connected,
              clients: clients,
              pickup_locations: pickup_locations,
              has_delhivery_profile: has_delhivery_profile?
            }
          end

          def ensure_profiles
            integ = integration || SpreeDelhivery::Integration.new(store: current_store)
            integ.ensure_delivery_profile_and_methods!

            render json: {
              success: true,
              has_delhivery_profile: has_delhivery_profile?
            }
          rescue StandardError => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def integration
            @integration ||= SpreeDelhivery::Integration.find_by(store: current_store)
          end

          def has_delhivery_profile
            profile = Spree::DeliveryProfiles::Shipping.find_by(name: 'Delhivery', store: current_store)
            return false if profile.nil?

            codes = profile.delivery_methods.pluck(:code)
            codes.include?('DELHIVERY_EXPRESS') && codes.include?('DELHIVERY_SURFACE')
          end
          alias has_delhivery_profile? has_delhivery_profile
        end
      end
    end
  end
end
