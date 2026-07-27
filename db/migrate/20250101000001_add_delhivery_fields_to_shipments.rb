class AddDelhiveryFieldsToShipments < ActiveRecord::Migration[6.1]
  def change
    unless column_exists?(:spree_shipments, :delhivery_waybill)
      add_column :spree_shipments, :delhivery_waybill, :string
    end
    unless column_exists?(:spree_shipments, :delhivery_ref_id)
      add_column :spree_shipments, :delhivery_ref_id, :string
    end
    unless column_exists?(:spree_shipments, :delhivery_label_url)
      add_column :spree_shipments, :delhivery_label_url, :text
    end
    unless column_exists?(:spree_shipments, :delhivery_response_data)
      add_column :spree_shipments, :delhivery_response_data, :json
    end

    add_index :spree_shipments, :delhivery_waybill unless index_exists?(:spree_shipments, :delhivery_waybill)
  end
end
