class AddDelhiveryToReturnAuthorizations < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:spree_return_authorizations, :delhivery_waybill)
      add_column :spree_return_authorizations, :delhivery_waybill, :string
    end
    unless column_exists?(:spree_return_authorizations, :delhivery_ref_id)
      add_column :spree_return_authorizations, :delhivery_ref_id, :string
    end
    unless column_exists?(:spree_return_authorizations, :delhivery_label_url)
      add_column :spree_return_authorizations, :delhivery_label_url, :string
    end
  end
end
