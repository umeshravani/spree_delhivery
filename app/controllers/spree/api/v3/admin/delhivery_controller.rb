# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Admin
        class DelhiveryController < Spree::Api::V3::Admin::BaseController
          skip_scope_check!

          def metadata
            token = params[:api_token].presence || integration&.preferred_api_token
            test_mode = if params[:test_mode].present?
                          ActiveModel::Type::Boolean.new.cast(params[:test_mode])
                        else
                          integration&.preferred_test_mode? || false
                        end

            profile_status = check_delhivery_profiles_status

            if token.blank?
              return render json: {
                connected: false,
                clients: [],
                pickup_locations: [],
                has_delhivery_profile: profile_status[:assigned],
                delhivery_info: profile_status
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
              has_delhivery_profile: profile_status[:assigned],
              delhivery_info: profile_status
            }
          end

          def ensure_profiles
            integ = integration || SpreeDelhivery::Integration.find_or_initialize_by(store: current_store)
            integ.ensure_delivery_profile_and_methods!

            profile_status = check_delhivery_profiles_status

            render json: {
              success: true,
              has_delhivery_profile: profile_status[:assigned],
              delhivery_info: profile_status
            }
          rescue StandardError => e
            render json: { error: e.message }, status: :unprocessable_entity
          end

          private

          def integration
            @integration ||= SpreeDelhivery::Integration.find_by(store: current_store)
          end

          def check_delhivery_profiles_status
            delhivery_profile = Spree::DeliveryProfile.find_by('LOWER(name) = ? AND store_id = ?', 'delhivery', current_store.id)

            delhivery_methods = Spree::DeliveryMethod.where(store_id: current_store.id).select do |m|
              m.name.to_s =~ /delhivery/i ||
                m.code.to_s =~ /delhivery/i ||
                m.rate_provider.to_s =~ /delhivery/i ||
                m.fulfillment_provider.to_s =~ /delhivery/i ||
                (m.respond_to?(:services) && m.services.any? { |s| s.carrier.to_s =~ /delhivery/i || s.service.to_s =~ /delhivery/i })
            end

            assigned = delhivery_profile.present? || delhivery_methods.any?
            profile_name = delhivery_profile&.name || delhivery_methods.first&.delivery_profile&.name || 'Delhivery'
            method_names = (delhivery_methods.map(&:name) + (delhivery_profile ? delhivery_profile.delivery_methods.pluck(:name) : [])).uniq

            {
              assigned: assigned,
              profile_name: profile_name,
              methods: method_names,
              is_default: delhivery_profile&.default? || false
            }
          end
        end
      end
    end
  end
end
