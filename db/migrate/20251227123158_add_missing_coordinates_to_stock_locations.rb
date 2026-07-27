class AddMissingCoordinatesToStockLocations < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:spree_stock_locations, :latitude)
      add_column :spree_stock_locations, :latitude, :decimal, precision: 10, scale: 6
    end

    unless column_exists?(:spree_stock_locations, :longitude)
      add_column :spree_stock_locations, :longitude, :decimal, precision: 10, scale: 6
    end

    unless column_exists?(:spree_stock_locations, :delhivery_warehouse_name)
      add_column :spree_stock_locations, :delhivery_warehouse_name, :string
    end
  end
end
