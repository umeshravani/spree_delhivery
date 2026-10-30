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

      # 1. Immediate idempotency guard: if a label or tracking number already exists, return it
      existing_waybill = resolve_existing_waybill(owner)
      if existing_waybill.present?
        return build_label_purchase(owner, integration, service_level, existing_waybill)
      end

      order_ref = order_reference_for(owner, order)

      # 2. Concurrency Control & Local Persistent Coordination:
      # Use database row-level locking on owner (if persisted and supports with_lock)
      # to prevent simultaneous requests from entering the booking block.
      acquire_booking_lock(owner) do |locked_owner|
        # Re-check inside lock after reload
        current_waybill = resolve_existing_waybill(locked_owner)
        if current_waybill.present?
          existing_waybill = current_waybill
          next
        end

        metadata = locked_owner.respond_to?(:metadata) && locked_owner.metadata.is_a?(Hash) ? locked_owner.metadata : {}
        state = metadata['delhivery_booking_state']
        started_at_str = metadata['delhivery_booking_started_at']
        started_at = started_at_str.present? ? (Time.zone.parse(started_at_str) rescue nil) : nil

        # If a booking is currently in progress within the past 45 seconds, reject concurrent call
        if state == 'in_progress' && started_at.present? && started_at > 45.seconds.ago
          raise Spree::Core::LabelPurchaseRefused, 'A Delhivery shipment booking is currently in progress for this fulfillment. Please wait a moment.'
        end

        # Mark in progress persistently
        record_booking_in_progress(locked_owner, ref: order_ref)
      end

      # If existing waybill was resolved inside lock, return it immediately
      if existing_waybill.present?
        return build_label_purchase(owner, integration, service_level, existing_waybill)
      end

      # 3. Pre-booking Carrier Idempotency Check:
      # Query Delhivery to check whether a package was already registered for this order reference.
      # This handles retries where a previous attempt was cut off by an ambiguous network timeout.
      existing_booking = integration.client.find_shipment_by_ref(ref_id: order_ref) rescue nil
      if existing_booking.present? && existing_booking[:waybill].present?
        waybill = existing_booking[:waybill]
        finalize_booking(owner, waybill: waybill, ref_id: order_ref)
        return build_label_purchase(owner, integration, service_level, waybill)
      end

      package = owner.to_package
      stock_location = owner.stock_location
      dest_address = is_return ? owner.ship_from_address : (owner.address || order&.ship_address)

      raise Spree::Core::LabelPurchaseRefused, 'Missing delivery address' if dest_address.blank?
      raise Spree::Core::LabelPurchaseRefused, 'Missing warehouse stock location' if stock_location.blank?

      # Sanitize Phone Numbers to strict 10-digits
      clean_dest_phone = dest_address.phone.to_s.gsub(/\D/, '').last(10)
      clean_return_phone = stock_location.phone.to_s.gsub(/\D/, '').last(10)

      # COD Detection for Orders
      is_cod = !is_return && order&.payments&.valid&.any? { |p| p.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod' }
      payment_mode = is_cod ? 'COD' : 'Pre-paid'
      cod_amount = is_cod ? order.total.to_f : 0.0

      # Spree 6 Marketplace Seller Detection
      seller = order.respond_to?(:seller) ? order.seller : nil
      seller_name = seller&.name.presence || owner.store.name

      # Exact Warehouse Matching & Dynamic Auto-Registration
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

      # Weight & Dimension Conversions
      weight_in_grams = SpreeDelhivery::MeasurementConverter.package_dead_weight_in_grams(package)
      shipment_length, shipment_width, shipment_height = SpreeDelhivery::MeasurementConverter.package_dimensions_in_cm(package)

      line_items_desc = package.contents.map { |item| "#{item.variant.name} (Qty: #{item.quantity}, Unit Price: #{item.price})" }.join(', ').truncate(250)
      full_dest_address = [dest_address.company, dest_address.address1, dest_address.address2].compact_blank.join(', ')

      shipment_data = {
        name: dest_address.full_name,
        add: full_dest_address,
        pin: dest_address.postal_code.to_s.strip,
        city: dest_address.city,
        state: (dest_address.respond_to?(:state_name_text) ? dest_address.state_name_text : (dest_address.state&.name || dest_address.state_name)),
        country: 'India',
        phone: clean_dest_phone,
        order: order_ref,
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

      # 4. Outbound API Execution with Ambiguous Network Timeout Reconciliation
      waybill = nil
      upload_wbn = nil
      sort_code = nil

      begin
        result = execute_shipment_creation(integration, payload, pickup_loc_name)
        waybill = result[:waybill]
        upload_wbn = result[:upload_wbn]
        sort_code = result[:sort_code]
      rescue Spree::Core::LabelPurchaseRefused
        clear_booking_in_progress(owner)
        raise
      rescue StandardError => e
        # Network timeout or communication failure: verify if Delhivery actually created the package
        reconciled = integration.client.find_shipment_by_ref(ref_id: order_ref) rescue nil
        if reconciled.present? && reconciled[:waybill].present?
          waybill = reconciled[:waybill]
        else
          clear_booking_in_progress(owner)
          Rails.error.report(e, context: { subject_id: owner.id, ref_id: order_ref }, source: 'spree_delhivery.fulfillment')
          raise Spree::Core::LabelPurchaseRefused, "Delhivery shipment error: #{e.message}"
        end
      end

      finalize_booking(owner, waybill: waybill, ref_id: order_ref, upload_wbn: upload_wbn, sort_code: sort_code)
      build_label_purchase(owner, integration, service_level, waybill, upload_wbn: upload_wbn, sort_code: sort_code)
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

    private

    def resolve_existing_waybill(owner)
      owner.tracking_number.presence ||
        (owner.respond_to?(:shipping_label) ? owner.shipping_label&.tracking_number.presence : nil) ||
        (owner.respond_to?(:metadata) && owner.metadata.is_a?(Hash) ? owner.metadata['delhivery_waybill'].presence : nil)
    end

    def order_reference_for(owner, order)
      ord_num = (order.respond_to?(:number) ? order.number : nil).presence
      own_num = (owner.respond_to?(:number) ? owner.number : nil).presence
      if own_num.present? && own_num != ord_num
        [ord_num, own_num].compact.join('-')
      else
        ord_num || own_num || (owner.respond_to?(:id) ? owner.id.to_s : 'DELHIVERY_REF')
      end
    end

    def acquire_booking_lock(owner)
      if owner.respond_to?(:with_lock) && owner.persisted?
        owner.with_lock do
          owner.reload if owner.persisted?
          yield(owner)
        end
      else
        yield(owner)
      end
    end

    def record_booking_in_progress(owner, ref:)
      return unless owner.respond_to?(:metadata)
      current_meta = owner.metadata.is_a?(Hash) ? owner.metadata : {}
      new_meta = current_meta.merge(
        'delhivery_booking_state' => 'in_progress',
        'delhivery_booking_started_at' => Time.current.iso8601,
        'delhivery_booking_ref' => ref
      )
      if owner.respond_to?(:update_column) && owner.persisted?
        owner.update_column(:metadata, new_meta)
      elsif owner.respond_to?(:metadata=)
        owner.metadata = new_meta
      end
    end

    def clear_booking_in_progress(owner)
      return unless owner.respond_to?(:metadata)
      current_meta = owner.metadata.is_a?(Hash) ? owner.metadata.dup : {}
      current_meta.delete('delhivery_booking_state')
      current_meta.delete('delhivery_booking_started_at')
      if owner.respond_to?(:update_column) && owner.persisted?
        owner.update_column(:metadata, current_meta)
      elsif owner.respond_to?(:metadata=)
        owner.metadata = current_meta
      end
    end

    def finalize_booking(owner, waybill:, ref_id:, upload_wbn: nil, sort_code: nil)
      return unless owner.respond_to?(:metadata)
      current_meta = owner.metadata.is_a?(Hash) ? owner.metadata.dup : {}
      current_meta.delete('delhivery_booking_state')
      current_meta.delete('delhivery_booking_started_at')
      current_meta['delhivery_waybill'] = waybill
      current_meta['delhivery_booking_ref'] = ref_id
      current_meta['delhivery_upload_wbn'] = upload_wbn if upload_wbn.present?
      current_meta['delhivery_sort_code'] = sort_code if sort_code.present?
      if owner.respond_to?(:update_column) && owner.persisted?
        owner.update_column(:metadata, current_meta)
      elsif owner.respond_to?(:metadata=)
        owner.metadata = current_meta
      end
    end

    def build_label_purchase(owner, integration, service_level, waybill, upload_wbn: nil, sort_code: nil)
      pdf_url = integration.client.fetch_packing_slip_url(waybill: waybill)
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
          'delhivery_upload_wbn' => upload_wbn,
          'delhivery_sort_code' => sort_code
        }.compact
      )
    end

    def execute_shipment_creation(integration, payload, pickup_loc_name)
      integration.client.create_shipment(payload: payload)
    rescue Spree::Core::LabelPurchaseRefused => e
      if e.message.include?('ClientWarehouse matching query does not exist') &&
         integration.preferred_pickup_location_name.present? &&
         pickup_loc_name != integration.preferred_pickup_location_name
        Rails.logger.warn("[Delhivery] Pickup location '#{pickup_loc_name}' not found on Delhivery. Retrying with master location: #{integration.preferred_pickup_location_name}")
        payload[:pickup_location] = { name: integration.preferred_pickup_location_name }
        integration.client.create_shipment(payload: payload)
      else
        raise
      end
    end
  end
end
