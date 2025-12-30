# Ensure all your custom fields are whitelisted
Spree::PermittedAttributes.stock_location_attributes << :latitude
Spree::PermittedAttributes.stock_location_attributes << :longitude
Spree::PermittedAttributes.stock_location_attributes << :delhivery_warehouse_name