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
      origin_zip = package.stock_location&.zipcode || package.stock_location&.postal_code

      return [] if destination_zip.blank? || origin_zip.blank?

      weight_in_grams = convert_weight(package)

      package_store = package.try(:store) || package.try(:owner)&.try(:store) || Spree::Current.store
      rate_currency = package_store&.default_currency || 'INR'

      rates = []

      # 1. Express (Air) Quote - Prepaid
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
          cost: express_cost,
          currency: rate_currency,
          metadata: { 'delhivery_mode' => 'Express', 'payment_type' => 'Pre-paid' }
        )
      end

      # 2. Surface Quote - Prepaid
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
          cost: surface_cost,
          currency: rate_currency,
          metadata: { 'delhivery_mode' => 'Surface', 'payment_type' => 'Pre-paid' }
        )
      end

      rates
    rescue StandardError => e
      dm_id = delivery_method.is_a?(Hash) ? delivery_method['id'] : delivery_method.try(:id) rescue nil
      Rails.error.report(e, context: { delivery_method_id: dm_id }, source: 'spree_delhivery.rating')
      []
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
      raw_weight = begin
        package.weight
      rescue StandardError
        0.5
      end
      raw_weight = 0.5 if raw_weight.nil? || raw_weight.to_f.zero?

      store_unit = package.try(:owner)&.try(:store)&.preferred_weight_unit rescue 'lb'
      store_unit ||= 'lb'

      converted = begin
        Spree::Measurement.convert_weight(raw_weight, from: store_unit, to: 'g').to_f.round(2)
      rescue StandardError
        (raw_weight.to_f * 453.592).round(2)
      end

      [converted, 50.0].max
    end

  end
end
