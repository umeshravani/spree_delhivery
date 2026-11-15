# frozen_string_literal: true

module SpreeDelhivery
  class DeliveryRateProvider < Spree::DeliveryRateProvider::Base
    def self.integration_class
      'SpreeDelhivery::Integration'
    end

    def self.provider_name
      'Delhivery'
    end

    def self.requires_address?
      true
    end

    def self.available?(store = Spree::Current.store)
      return false if store.nil?

      store.integrations.active.where(type: integration_class).exists?
    end

    def self.service_catalog(integration)
      Spree::DeliveryRateProvider::ServiceCatalog.listing(
        [
          { carrier: 'Delhivery', service: 'Express', label: 'Delhivery Express (Air)' },
          { carrier: 'Delhivery', service: 'Surface', label: 'Delhivery Surface' }
        ]
      )
    end

    def estimates(package)
      active_integration = current_integration(package)
      return [] if active_integration.nil?

      ship_address = package.respond_to?(:ship_address) ? package.ship_address : nil
      ship_address ||= package.try(:owner)&.try(:ship_address)
      ship_address ||= package.try(:order)&.try(:ship_address)
      ship_address ||= package.try(:address)

      destination_zip = ship_address&.postal_code || ship_address&.zipcode
      return [] if destination_zip.blank?

      origin_zip = package.stock_location&.zipcode.presence ||
                   package.stock_location&.postal_code.presence ||
                   Spree::StockLocation.where.not(zipcode: [nil, '']).first&.zipcode ||
                   '110001'

      weight_in_grams = convert_weight(package)

      package_store = package.try(:store) || package.try(:owner)&.try(:store) || Spree::Current.store
      rate_currency = package.try(:currency) || package.try(:owner)&.try(:currency) || package.try(:order)&.try(:currency) || package_store&.default_currency || 'INR'

      rates = []

      # 1. Express (Air) Quote - Prepaid
      begin
        express_cost = active_integration.client.calculate_rate(
          origin_pin: origin_zip,
          destination_pin: destination_zip,
          weight_in_grams: weight_in_grams,
          mode: 'E',
          payment_type: 'Pre-paid'
        )

        if express_cost && express_cost > 0
          rates << Spree::DeliveryRateProvider::Estimate.new(
            carrier: 'Delhivery',
            service_level: 'Express',
            name: 'Delhivery Express (Air)',
            cost: express_cost.to_d,
            currency: rate_currency,
            metadata: { 'delhivery_mode' => 'Express', 'payment_type' => 'Pre-paid' }
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[Delhivery] Express rate calculation failed: #{e.message}")
      end

      # 2. Surface Quote - Prepaid
      begin
        surface_cost = active_integration.client.calculate_rate(
          origin_pin: origin_zip,
          destination_pin: destination_zip,
          weight_in_grams: weight_in_grams,
          mode: 'S',
          payment_type: 'Pre-paid'
        )

        if surface_cost && surface_cost > 0
          rates << Spree::DeliveryRateProvider::Estimate.new(
            carrier: 'Delhivery',
            service_level: 'Surface',
            name: 'Delhivery Surface',
            cost: surface_cost.to_d,
            currency: rate_currency,
            metadata: { 'delhivery_mode' => 'Surface', 'payment_type' => 'Pre-paid' }
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[Delhivery] Surface rate calculation failed: #{e.message}")
      end

      # Fallback rates: if API rate lookup returned empty (e.g. staging, test token, or network error),
      # NEVER return empty rates because returning empty deletes fulfillments and breaks checkout.
      if rates.empty?
        rates << Spree::DeliveryRateProvider::Estimate.new(
          carrier: 'Delhivery',
          service_level: 'Surface',
          name: 'Delhivery Surface',
          cost: 99.0.to_d,
          currency: rate_currency,
          metadata: { 'delhivery_mode' => 'Surface', 'payment_type' => 'Pre-paid', 'fallback' => true }
        )
        rates << Spree::DeliveryRateProvider::Estimate.new(
          carrier: 'Delhivery',
          service_level: 'Express',
          name: 'Delhivery Express (Air)',
          cost: 149.0.to_d,
          currency: rate_currency,
          metadata: { 'delhivery_mode' => 'Express', 'payment_type' => 'Pre-paid', 'fallback' => true }
        )
      end

      rates
    rescue StandardError => e
      dm_id = delivery_method.is_a?(Hash) ? delivery_method['id'] : delivery_method.try(:id) rescue nil
      Rails.error.report(e, context: { delivery_method_id: dm_id }, source: 'spree_delhivery.rating')
      if destination_zip.present?
        [
          Spree::DeliveryRateProvider::Estimate.new(
            carrier: 'Delhivery',
            service_level: 'Surface',
            name: 'Delhivery Surface',
            cost: 99.0.to_d,
            currency: rate_currency || 'INR',
            metadata: { 'delhivery_mode' => 'Surface', 'payment_type' => 'Pre-paid', 'fallback' => true }
          ),
          Spree::DeliveryRateProvider::Estimate.new(
            carrier: 'Delhivery',
            service_level: 'Express',
            name: 'Delhivery Express (Air)',
            cost: 149.0.to_d,
            currency: rate_currency || 'INR',
            metadata: { 'delhivery_mode' => 'Express', 'payment_type' => 'Pre-paid', 'fallback' => true }
          )
        ]
      else
        []
      end
    end

    private

    def current_integration(package)
      subject = package.respond_to?(:owner) && package.owner.present? ? package.owner : package
      target = subject.respond_to?(:id) ? subject : (package.respond_to?(:order) ? package.order : nil)

      if target.present?
        integration_for(target) rescue nil || SpreeDelhivery::Integration.active.first
      else
        SpreeDelhivery::Integration.active.first
      end
    end

    def convert_weight(package)
      SpreeDelhivery::MeasurementConverter.chargeable_weight_in_grams(package)
    rescue StandardError => e
      Rails.logger.warn("[Delhivery] Error calculating chargeable weight: #{e.message}")
      500
    end

  end
end
