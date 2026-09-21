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

      package = owner.to_package
      stock_location = owner.stock_location
      dest_address = is_return ? owner.ship_from_address : (owner.address || order&.ship_address)

      raise Spree::Core::LabelPurchaseRefused, 'Missing delivery address' if dest_address.blank?
      raise Spree::Core::LabelPurchaseRefused, 'Missing warehouse stock location' if stock_location.blank?

# 1. Sanitize Phone Numbers to strict 10-digits
clean_dest_phone = dest_address.phone.to_s.gsub(/\D/, '').last(10)
clean_return_phone = stock_location.phone.to_s.gsub(/\D/, '').last(10)

      service_level = owner.selected_delivery_rate&.service_level || 'Express'
      shipping_mode = service_level == 'Surface' ? 'Surface' : 'Express'

      # 1. COD Detection for Split Orders
      is_cod = !is_return && order&.payments&.valid&.any? { |p| p.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod' }
      payment_mode = is_cod ? 'COD' : 'Pre-paid'
      cod_amount = is_cod ? order.total.to_f : 0.0

      # 2. Spree 6 Marketplace Seller Detection
      seller = order.respond_to?(:seller) ? order.seller : nil
      seller_name = seller&.name.presence || owner.store.name

      # 3. Exact Warehouse Matching & Dynamic Auto-Registration
      # In a multi-vendor marketplace, the vendor warehouse must exist in Delhivery.
      # Automatically ensure the stock location is registered with Delhivery.
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

      # 2. Convert Weight to Grams
      weight_in_grams = Spree::Measurement.convert_weight(
        package.weight,
        from: (owner.store&.preferred_weight_unit || 'lb'),
        to: 'g'
      ).to_f.round(2)
      weight_in_grams = [weight_in_grams, 50.0].max.to_i

      # 3. Convert Dimensions to Centimeters
      dim_unit = (owner.store.respond_to?(:preferred_dimension_unit) ? owner.store.preferred_dimension_unit : (owner.store&.metric_unit_system? ? 'cm' : 'in')) || 'cm'
      max_length = package.contents.map { |item| Spree::Measurement.convert_length(item.variant.depth || 10.0, from: dim_unit, to: 'cm').to_f }.max || 10.0
      max_width  = package.contents.map { |item| Spree::Measurement.convert_length(item.variant.width || 10.0, from: dim_unit, to: 'cm').to_f }.max || 10.0
      max_height = package.contents.map { |item| Spree::Measurement.convert_length(item.variant.height || 10.0, from: dim_unit, to: 'cm').to_f }.max || 10.0

      # 4. Improve Product Description for Packing Slip
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
        shipment_length: max_length.ceil,
        shipment_width: max_width.ceil,
        shipment_height: max_height.ceil,
        shipping_mode: shipping_mode
      }

      payload = {
        shipments: [shipment_data],
        pickup_location: { name: pickup_loc_name }
      }

      # 1. Book shipment on Delhivery (with resilient fallback to integration default warehouse)
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

      # 2. Fetch the authentic Delhivery shipping label PDF download URL (4x6 thermal format)
      pdf_url = integration.client.fetch_packing_slip_url(waybill: waybill)

      # 3. Return Spree::LabelPurchase (Core attaches the PDF via StoreFileJob)
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

    def self.generate_label_pdf(waybill:, order_number:, consignee_name:, address:, city:, pin:, phone:, service:, mode:, seller_name: 'Artolika Hub', length_cm: 7, width_cm: 30, height_cm: 20, weight_gm: 500, total_amount: 1128.54, seller_gstin: 'URP')
      clean = ->(str) { str.to_s.gsub(/[()\\\r\n]/, ' ').strip.first(45) }
      c_name = clean.call(consignee_name)
      c_addr = clean.call(address)
      c_city = clean.call("#{city} - #{pin}")
      c_phone = clean.call(phone)
      c_phone_masked = c_phone.length == 10 ? "XXXXXX#{c_phone.last(4)}" : c_phone
      s_name = clean.call(seller_name)

      <<~PDF
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 6 0 R >> >> /Contents 5 0 R >> endobj
        4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >> endobj
        6 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
        5 0 obj << /Length 2800 >> stream
        0.15 0.39 0.92 RG
        1.5 w
        42 42 510 758 re S
        0.12 0.23 0.54 rg
        42 740 510 60 re f
        1 1 1 rg
        BT
        /F1 16 Tf
        60 770 Td
        (DELHIVERY EXPRESS COURIER) Tj
        /F2 10 Tf
        0 -18 Td
        (PACKING SLIP & SHIPPING MANIFEST - A4 PRINT LAYOUT) Tj
        ET
        0.06 0.72 0.51 rg
        430 755 100 24 re f
        1 1 1 rg
        BT
        /F1 11 Tf
        445 762 Td
        (#{mode.upcase}) Tj
        ET
        0 0 0 RG
        1 w
        42 660 510 70 re S
        0 0 0 rg
        BT
        /F1 12 Tf
        55 710 Td
        (WAYBILL / TRACKING NO: #{waybill}) Tj
        /F2 10 Tf
        250 0 Td
        (ORDER ID: #{order_number}) Tj
        /F2 9 Tf
        -250 -20 Td
        (DESTINATION HUB: DEL/MPP | ROUTING: Delhi Motiakhan_D) Tj
        0 -15 Td
        (MODE: #{mode} | SERVICE: #{service}) Tj
        ET
        55 668 m 55 685 l S 58 668 m 58 685 l S 62 668 m 62 685 l S 65 668 m 65 685 l S 70 668 m 70 685 l S 75 668 m 75 685 l S 80 668 m 80 685 l S 86 668 m 86 685 l S 92 668 m 92 685 l S 98 668 m 98 685 l S 105 668 m 105 685 l S 112 668 m 112 685 l S 120 668 m 120 685 l S 128 668 m 128 685 l S 136 668 m 136 685 l S 145 668 m 145 685 l S 155 668 m 155 685 l S 165 668 m 165 685 l S 175 668 m 175 685 l S 185 668 m 185 685 l S 195 668 m 195 685 l S 205 668 m 205 685 l S 215 668 m 215 685 l S 225 668 m 225 685 l S 235 668 m 235 685 l S
        0.95 0.96 0.98 rg
        42 620 510 32 re f
        0 0 0 rg
        BT
        /F1 10 Tf
        55 632 Td
        (PACKAGE SPECS:) Tj
        /F2 9 Tf
        110 0 Td
        (DIMENSIONS: #{length_cm} x #{width_cm} x #{height_cm} cm  |  WEIGHT: #{weight_gm} gm  |  PIECES: 1) Tj
        ET
        42 440 248 170 re S
        BT
        /F1 10 Tf
        55 590 Td
        (SHIP TO / CONSIGNEE:) Tj
        /F2 9 Tf
        0 -18 Td
        (#{c_name}) Tj
        0 -14 Td
        (Phone: #{c_phone_masked}) Tj
        0 -14 Td
        (#{c_addr}) Tj
        0 -14 Td
        (#{c_city}) Tj
        ET
        304 440 248 170 re S
        BT
        /F1 10 Tf
        317 590 Td
        (SELLER / RETURN LOCATION:) Tj
        /F2 9 Tf
        0 -18 Td
        (#{s_name}) Tj
        0 -14 Td
        (6-6-743/4/A, Opp Adarsh Nagar Road) Tj
        0 -14 Td
        (Ambedkar Nagar, Karim Nagar) Tj
        0 -14 Td
        (Telangana - 505001, India) Tj
        0 -14 Td
        (GSTIN: #{seller_gstin}) Tj
        ET
        42 150 510 270 re S
        0.12 0.23 0.54 rg
        42 390 510 30 re f
        1 1 1 rg
        BT
        /F1 9 Tf
        52 400 Td
        (SKU) Tj
        120 0 Td
        (ITEM DESCRIPTION) Tj
        250 0 Td
        (QTY) Tj
        290 0 Td
        (HSN) Tj
        340 0 Td
        (TAX) Tj
        390 0 Td
        (UNIT PRICE) Tj
        460 0 Td
        (TOTAL) Tj
        ET
        0.97 0.98 0.98 rg
        42 355 510 35 re f
        0 0 0 rg
        BT
        /F2 9 Tf
        52 368 Td
        (APP-GAD-001) Tj
        120 0 Td
        (Test Apparel / Gadget) Tj
        250 0 Td
        (1) Tj
        290 0 Td
        (61091000) Tj
        340 0 Td
        (18%) Tj
        390 0 Td
        (Rs. 999.00) Tj
        460 0 Td
        (Rs. #{total_amount}) Tj
        ET
        42 60 510 80 re S
        BT
        /F1 10 Tf
        350 120 Td
        (Subtotal:) Tj
        110 0 Td
        (Rs. 999.00) Tj
        /F2 9 Tf
        -110 -18 Td
        (Shipping & Taxes:) Tj
        110 0 Td
        (Rs. 129.54) Tj
        /F1 11 Tf
        -110 -22 Td
        (Grand Total:) Tj
        110 0 Td
        (Rs. #{total_amount}) Tj
        ET
        BT
        /F2 8 Tf
        120 48 Td
        (Delhivery Express Courier Services - Official Packing Slip & Shipping Manifest) Tj
        ET
        endstream endobj
        xref
        0 7
        0000000000 65535 f 
        0000000009 00000 n 
        0000000058 00000 n 
        0000000115 00000 n 
        0000000260 00000 n 
        0000000384 00000 n 
        0000000330 00000 n 
        trailer << /Size 7 /Root 1 0 R >>
        startxref
        3250
        %%EOF
      PDF
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

    # Customs forms only; the label is attached to Spree::ShippingLabel.file
    def documents(_owner)
      []
    end
  end
end
