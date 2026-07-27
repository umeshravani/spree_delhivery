class AddTrackingStatusToShipments < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:spree_shipments, :tracking_status)
      add_column :spree_shipments, :tracking_status, :string
    end

    unless column_exists?(:spree_shipments, :delhivery_response_data)
      add_column :spree_shipments, :delhivery_response_data, :jsonb
    end
  end
end
