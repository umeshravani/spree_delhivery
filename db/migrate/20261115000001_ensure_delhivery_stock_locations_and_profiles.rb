# frozen_string_literal: true

class EnsureDelhiveryStockLocationsAndProfiles < ActiveRecord::Migration[7.2]
  def up
    # 1. Ensure stock locations have valid origin zipcode and country
    Spree::StockLocation.where(zipcode: [nil, '']).find_each do |loc|
      loc.update_columns(zipcode: '110001', city: 'New Delhi', address1: 'Warehouse Hub', country_code: 'IN')
    end

    # 2. Ensure each store has active Delhivery integration, profile, methods, and COD
    Spree::Store.all.each do |store|
      integ = store.integrations.find_or_initialize_by(type: 'SpreeDelhivery::Integration')
      integ.name = 'Delhivery' if integ.name.blank?
      integ.save! if integ.new_record?
      integ.ensure_delivery_profile_and_methods!
    end

    # 3. Clean payment method name
    Spree::PaymentMethod::DelhiveryCod.update_all(name: 'Cash on Delivery')
  end

  def down
    # Reversible no-op
  end
end
