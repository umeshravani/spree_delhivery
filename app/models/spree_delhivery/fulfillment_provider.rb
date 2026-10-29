# frozen_string_literal: true

module SpreeDelhivery
  class FulfillmentProvider < Spree::FulfillmentProvider::Base
    def self.integration_class
      'SpreeDelhivery::Integration'
    end

    def self.provider_name
      'Delhivery'
    end

    def self.generates_labels?
      true
    end

    def purchase_label(owner)
      integration = integration_for(owner)
      return if integration.nil?

      is_return = owner.is_a?(Spree::Return)
      order = is_return ? owner.order : owner.order

      service_level = owner.selected_delivery_rate&.service_level || 'Express'
      shipping_mode = service_level == 'Surface' ? 'Surface' : 'Express'

      # Idempotency guard: if a label or tracking number already exists, do not book a duplicate shipment
      existing_waybill = owner.tracking_number.presence || (owner.respond_to?(:shipping_label) ? owner.shipping_label&.tracking_number : nil)
      if existing_waybill.present?
        pdf_url = integration.client.fetch_packing_slip_url(waybill: existing_waybill)
        return Spree::LabelPurchase.new(
          external_id: existing_waybill,
          carrier: 'Delhivery',
          service: service_level,
          tracking_number: existing_waybill,
          tracking_url: "https://www.delhivery.com/track/package/#{existing_waybill}",
          cost: owner.selected_delivery_rate&.cost || 0.0,
          currency: owner.store.default_currency || 'INR',
          format: 'pdf',
          file_url: pdf_url,
          metadata: { 'delhivery_waybill' => existing_waybill }
        )
      end

      package = owner.to_package
      stock_location = owner.stock_location
      dest_address = is_return ? owner.ship_from_address : (owner.address || order&.ship_address)

      raise Spree::Core::LabelPurchaseRefused, 'Missing delivery address' if dest_address.blank?
      raise Spree::Core::LabelPurchaseRefused, 'Missing warehouse stock location' if stock_location.blank?

      # 1. Sanitize Phone Numbers to strict 10-digits
      clean_dest_phone = dest_address.phone.to_s.gsub(/\D/, '').last(10)
      clean_return_phone = stock_location.phone.to_s.gsub(/\D/, '').last(10)

      # 1. COD Detection for Orders
      is_cod = !is_return && order&.payments&.valid&.any? { |p| p.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod' }
      payment_mode = is_cod ? 'COD' : 'Pre-paid'
      cod_amount = is_cod ? order.total.to_f : 0.0

      # 2. Spree 6 Marketplace Seller Detection
      seller = order.respond_to?(:seller) ? order.seller : nil
      seller_name = seller&.name.presence || owner.store.name

      # 3. Exact Warehouse Matching & Dynamic Auto-Registration
      pickup_loc_name = stock_location.name
      begin
        warehouse_addr = [stock_location.address1, stock_location.address2].compact_blank.join(', ')
        warehouse_phone = clean_return_phone.presence || clean_dest_phone.presence || '9999999999'
        integration.client.register_warehouse(
          name: stock_location.name,
          address: warehouse_addr.presence || stock_location.name,
          city: stock_location.city,
          pin: stock_location.zipcode,
          phone: warehouse_phone,
          registered_name: stock_location.company.presence || seller_name
        )
      rescue StandardError => e
        Rails.logger.warn("[Delhivery] Auto-registration of warehouse #{stock_location.name} failed: #{e.message}")
      end

      # 4. Convert Weight to Grams (Accurately converts from variant's UOM: g, kg, lb, oz)
      weight_in_grams = SpreeDelhivery::MeasurementConverter.package_dead_weight_in_grams(package)

      # 5. Convert Dimensions to Centimeters (Accurately converts from variant's UOM: mm, cm, m, in, ft)
      shipment_length, shipment_width, shipment_height = SpreeDelhivery::MeasurementConverter.package_dimensions_in_cm(package)

      # 6. Improve Product Description for Packing Slip
      line_items_desc = package.contents.map { |item| "#{item.variant.name} (Qty: #{item.quantity}, Unit Price: #{item.price})" }.join(', ').truncate(250)
      full_dest_address = [dest_address.company, dest_address.address1, dest_address.address2].compact_blank.join(', ')

      # Build the official CMU shipment payload
      shipment_data = {
        name: dest_address.full_name,
        add: full_dest_address,
        pin: dest_address.postal_code.to_s.strip,
        city: dest_address.city,
        state: (dest_address.respond_to?(:state_name_text) ? dest_address.state_name_text : (dest_address.state&.name || dest_address.state_name)),
        country: 'India',
        phone: clean_dest_phone,
        order: order.number,
        payment_mode: payment_mode,
        return_pin: stock_location.zipcode.to_s.strip,
        return_city: stock_location.city,
        return_phone: clean_return_phone,
        return_add: [stock_location.address1, stock_location.address2].compact_blank.join(', '),
        return_state: (stock_location.respond_to?(:state_name_text) ? stock_location.state_name_text : (stock_location.state&.name || stock_location.state_name)),
        return_country: 'India',
        products_desc: line_items_desc,
        cod_amount: cod_amount,
        order_date: order.completed_at || order.created_at || Time.current,
        total_amount: order.total.to_f,
        seller_add: [stock_location.address1, stock_location.address2].compact_blank.join(', ').truncate(200),
        seller_name: seller_name.truncate(50),
        seller_inv: order.number,
        quantity: package.contents.sum(&:quantity),
        waybill: '',
        weight: weight_in_grams,
        shipment_length: shipment_length,
        shipment_width: shipment_width,
        shipment_height: shipment_height,
        shipping_mode: shipping_mode
      }

      payload = {
        shipments: [shipment_data],
        pickup_location: { name: pickup_loc_name }
      }

      # 7. Book shipment on Delhivery (with resilient fallback to integration default warehouse)
      begin
        result = integration.client.create_shipment(payload: payload)
      rescue Spree::Core::LabelPurchaseRefused => e
        if e.message.include?('ClientWarehouse matching query does not exist') &&
           integration.preferred_pickup_location_name.present? &&
           pickup_loc_name != integration.preferred_pickup_location_name
          Rails.logger.warn("[Delhivery] Pickup location '#{pickup_loc_name}' not found on Delhivery. Retrying with master location: #{integration.preferred_pickup_location_name}")
          payload[:pickup_location] = { name: integration.preferred_pickup_location_name }
          result = integration.client.create_shipment(payload: payload)
        else
          raise
        end
      end
      waybill = result[:waybill]

      # 8. Fetch the authentic Delhivery shipping label PDF download URL (4x6 thermal format)
      pdf_url = integration.client.fetch_packing_slip_url(waybill: waybill)

      # 9. Return Spree::LabelPurchase (Core attaches the PDF via StoreFileJob)
      Spree::LabelPurchase.new(
        external_id: waybill,
        carrier: 'Delhivery',
        service: service_level,
        tracking_number: waybill,
        tracking_url: "https://www.delhivery.com/track/package/#{waybill}",
        cost: owner.selected_delivery_rate&.cost || 0.0,
        currency: owner.store.default_currency || 'INR',
        format: 'pdf',
        file_url: pdf_url,
        metadata: {
          'delhivery_waybill' => waybill,
          'delhivery_upload_wbn' => result[:upload_wbn],
          'delhivery_sort_code' => result[:sort_code]
        }.compact
      )
    rescue Spree::Core::LabelPurchaseRefused
      raise
    rescue StandardError => e
      Rails.error.report(e, context: { subject_id: owner.id }, source: 'spree_delhivery.fulfillment')
      raise Spree::Core::LabelPurchaseRefused, "Delhivery shipment error: #{e.message}"
    end

    def refund_label(shipping_label)
      integration = shipping_label.integration || integration_for(shipping_label.owner)
      return false if integration.nil? || shipping_label.tracking_number.blank?

      integration.client.cancel_shipment(waybill: shipping_label.tracking_number)
      'refunded'
    rescue StandardError
      false
    end

    def tracking_url(delivery)
      return if delivery.shipping_label.blank?

      "https://www.delhivery.com/track/package/#{delivery.shipping_label.tracking_number}"
    end

    def documents(_owner)
      []
    end
  end
end
