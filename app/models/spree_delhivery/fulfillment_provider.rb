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
      order = owner.respond_to?(:order) ? owner.order : nil

      selected_rate = owner.respond_to?(:selected_delivery_rate) ? owner.selected_delivery_rate : nil
      service_level = selected_rate&.service_level.presence || 'Express'
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
      needs_reconciliation = false

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
        started_at = started_at_str.present? ? (Time.zone&.parse(started_at_str) || Time.parse(started_at_str) rescue nil) : nil

        # If a booking is currently in progress within the past 45 seconds, reject concurrent call
        if state == 'in_progress' && started_at.present? && started_at > 45.seconds.ago
          raise Spree::Core::LabelPurchaseRefused, 'A Delhivery shipment booking is currently in progress for this fulfillment. Please wait a moment.'
        end

        # If previous booking state was requires_reconciliation or an expired in_progress (e.g. worker crashed)
        if state == 'requires_reconciliation' || (state == 'in_progress' && (started_at.nil? || started_at <= 45.seconds.ago))
          needs_reconciliation = true
          next
        end

        # Mark in progress persistently
        record_booking_in_progress(locked_owner, ref: order_ref)
      end

      # If existing waybill was resolved inside lock, return it immediately
      if existing_waybill.present?
        return build_label_purchase(owner, integration, service_level, existing_waybill)
      end

      # 3. Pre-booking Carrier Reconciliation & Idempotency Check:
      # If previous attempt timed out or crashed, prevent automatic rebooking until carrier confirms package status.
      if needs_reconciliation
        existing_booking = integration.client.find_shipment_by_ref(ref_id: order_ref) rescue nil
        if existing_booking.present? && existing_booking[:waybill].present?
          waybill = existing_booking[:waybill]
          finalize_booking(owner, waybill: waybill, ref_id: order_ref)
          return build_label_purchase(owner, integration, service_level, waybill)
        else
          record_booking_ambiguous(owner, ref: order_ref)
          raise Spree::Core::LabelPurchaseRefused, "Shipment booking outcome for #{order_ref} is ambiguous following a prior timeout or crash. Automatic rebooking is paused to prevent duplicate carrier manifests. Please verify reference '#{order_ref}' in Delhivery portal (https://one.delhivery.com) or retry once tracking updates."
        end
      end

      # Pre-booking check for normal retries
      existing_booking = integration.client.find_shipment_by_ref(ref_id: order_ref) rescue nil
      if existing_booking.present? && existing_booking[:waybill].present?
        waybill = existing_booking[:waybill]
        finalize_booking(owner, waybill: waybill, ref_id: order_ref)
        return build_label_purchase(owner, integration, service_level, waybill)
      end

      package = owner.to_package
      stock_location = owner.stock_location
      dest_address = resolve_destination_address(owner, order, is_return)

      raise Spree::Core::LabelPurchaseRefused, 'Missing delivery address' if dest_address.blank?
      raise Spree::Core::LabelPurchaseRefused, 'Missing warehouse stock location' if stock_location.blank?

      # Sanitize Phone Numbers to strict 10-digits
      clean_return_phone = sanitize_phone(stock_location.phone)
      clean_dest_phone = sanitize_phone(dest_address.phone).presence || clean_return_phone.presence || '9999999999'
      clean_return_phone = clean_return_phone.presence || clean_dest_phone

      # COD / Reverse Pickup Detection for Orders & Returns
      cod_payments = if is_return || order.nil?
                       []
                     else
                       valid_order_payments(order).select do |payment|
                         payment.payment_method&.type == 'Spree::PaymentMethod::DelhiveryCod'
                       end
                     end
      is_cod = !is_return && cod_payments.any?
      payment_mode = if is_return
                       'Pickup'
                     elsif is_cod
                       'COD'
                     else
                       'Pre-paid'
                     end
      cod_amount = if is_cod
                     amount = cod_payments.sum { |p| p.amount.to_f }.round(2)
                     amount.positive? ? amount : order.total.to_f.round(2)
                   else
                     0.0
                   end

      # Spree 6 Marketplace Seller Detection
      seller = order.respond_to?(:seller) ? order.seller : nil
      seller_name = seller&.name.presence || owner.store&.name.presence || 'Spree Store'

      # Warehouse / Pickup Location Resolution:
      # When the store uses a generic default warehouse (e.g. "Shop location") alongside a configured
      # Delhivery Pickup Location in Integration settings (e.g. "Artolika HUB"), prefer the master
      # pickup location unless this fulfillment ships from a custom / seller-specific stock location.
      preferred_pickup = integration.respond_to?(:preferred_pickup_location_name) ? integration.preferred_pickup_location_name.to_s.strip.presence : nil
      seller_location = stock_location.respond_to?(:seller_id) && stock_location.seller_id.present?
      default_location = stock_location.respond_to?(:default?) ? stock_location.default? : true
      pickup_loc_name = if !seller_location && default_location && preferred_pickup.present?
                          preferred_pickup
                        else
                          stock_location.name.presence || preferred_pickup
                        end

      if pickup_loc_name.present? && pickup_loc_name == stock_location.name && pickup_loc_name != preferred_pickup
        begin
          warehouse_addr = [stock_location.address1, stock_location.address2].compact_blank.join(', ')
          integration.client.register_warehouse(
            name: stock_location.name,
            address: warehouse_addr.presence || stock_location.name,
            city: stock_location.city,
            pin: stock_location.zipcode,
            phone: clean_return_phone,
            registered_name: stock_location.company.presence || seller_name
          )
        rescue StandardError => e
          Rails.logger.warn("[Delhivery] Auto-registration of warehouse #{stock_location.name} failed: #{e.message}")
        end
      end

      # Weight & Dimension Conversions
      weight_in_grams = SpreeDelhivery::MeasurementConverter.package_dead_weight_in_grams(package)
      shipment_length, shipment_width, shipment_height = SpreeDelhivery::MeasurementConverter.package_dimensions_in_cm(package)

      line_items_desc = package.contents.map do |item|
        name = item.variant&.name.presence || 'Item'
        qty = item.respond_to?(:quantity) ? item.quantity : 1
        unit_price = item.respond_to?(:price) ? item.price : 0
        "#{name} (Qty: #{qty}, Unit Price: #{unit_price})"
      end.join(', ').gsub(/[\r\n\t]+/, ' ').strip.truncate(250)
      line_items_desc = "Order #{order_ref}" if line_items_desc.blank?

      dest_company = dest_address.respond_to?(:company) ? dest_address.company : nil
      dest_postal = dest_address.respond_to?(:postal_code) ? dest_address.postal_code : (dest_address.respond_to?(:zipcode) ? dest_address.zipcode : nil)
      full_dest_address = [dest_company, dest_address.address1, dest_address.address2].compact_blank.join(', ').gsub(/[\r\n\t]+/, ' ').strip
      full_dest_address = dest_address.city.to_s if full_dest_address.blank?

      return_address_str = [stock_location.address1, stock_location.address2].compact_blank.join(', ').gsub(/[\r\n\t]+/, ' ').strip
      return_address_str = pickup_loc_name.to_s if return_address_str.blank?

      dest_name = (dest_address.respond_to?(:full_name) ? dest_address.full_name : nil).presence || 'Customer'
      dest_state = resolve_state_name(dest_address)
      return_state = resolve_state_name(stock_location)
      order_timestamp = (order&.respond_to?(:completed_at) && order.completed_at) ||
                        (order&.respond_to?(:created_at) && order.created_at) ||
                        Time.current
      order_total = order.respond_to?(:total) && order.total.present? ? order.total.to_f.round(2) : 0.0
      inv_number = (order&.respond_to?(:number) ? order.number : nil).presence || order_ref

      shipment_data = {
        name: dest_name,
        add: full_dest_address,
        pin: dest_postal.to_s.strip,
        city: dest_address.city.to_s.strip,
        state: dest_state,
        country: 'India',
        phone: clean_dest_phone,
        order: order_ref,
        payment_mode: payment_mode,
        return_pin: stock_location.zipcode.to_s.strip,
        return_city: stock_location.city.to_s.strip,
        return_phone: clean_return_phone,
        return_add: return_address_str,
        return_state: return_state,
        return_country: 'India',
        products_desc: line_items_desc,
        cod_amount: cod_amount,
        order_date: order_timestamp.strftime('%Y-%m-%d %H:%M:%S'),
        total_amount: order_total,
        seller_add: return_address_str.truncate(200),
        seller_name: seller_name.to_s.truncate(50),
        seller_inv: inv_number.to_s.truncate(50),
        quantity: [package.contents.sum(&:quantity).to_i, 1].max,
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
          # Mark state as requires_reconciliation to prevent automatic duplicate rebooking
          record_booking_ambiguous(owner, ref: order_ref)
          Rails.error.report(e, context: { subject_id: owner.id, ref_id: order_ref }, source: 'spree_delhivery.fulfillment')
          raise Spree::Core::LabelPurchaseRefused, "Delhivery shipment error: #{e.message}. State marked as requires_reconciliation to pause automatic rebooking."
        end
      end

      finalize_booking(owner, waybill: waybill, ref_id: order_ref, upload_wbn: upload_wbn, sort_code: sort_code)
      build_label_purchase(owner, integration, service_level, waybill, upload_wbn: upload_wbn, sort_code: sort_code)
    end

    def create_fulfillment(_fulfillment)
      {}
    end

    def cancel_fulfillment(fulfillment)
      integration = integration_for(fulfillment)
      waybill = resolve_existing_waybill(fulfillment)
      if integration && waybill.present?
        cancelled = integration.client.cancel_shipment(waybill: waybill)
        clear_booking_waybill_metadata(fulfillment) if cancelled
      end
      true
    rescue StandardError => e
      Rails.logger.warn("[Delhivery] Cancel fulfillment warning: #{e.message}") if defined?(Rails)
      true
    end

    def refund_label(shipping_label)
      integration = shipping_label.integration || integration_for(shipping_label.owner)
      return false if integration.nil? || shipping_label.tracking_number.blank?

      cancelled = integration.client.cancel_shipment(waybill: shipping_label.tracking_number)
      return false unless cancelled

      clear_booking_waybill_metadata(shipping_label.owner) if shipping_label.respond_to?(:owner) && shipping_label.owner.present?
      'refunded'
    rescue StandardError
      false
    end

    def tracking_url(delivery)
      label = delivery.respond_to?(:shipping_label) ? delivery.shipping_label : nil
      tracking = label&.tracking_number.presence || (delivery.respond_to?(:tracking_number) ? delivery.tracking_number.presence : nil)
      return if tracking.blank?

      "https://www.delhivery.com/track/package/#{tracking}"
    end

    def documents(_owner)
      []
    end

    private

    def resolve_existing_waybill(owner)
      return owner.tracking_number if owner.respond_to?(:tracking_number) && owner.tracking_number.present?

      if owner.respond_to?(:shipping_labels) && owner.shipping_labels.present?
        active_label = owner.shipping_labels.detect do |label|
          status = label.respond_to?(:status) ? label.status.to_s : 'purchased'
          status != 'refunded' && label.respond_to?(:tracking_number) && label.tracking_number.present?
        end
        return active_label.tracking_number if active_label&.tracking_number.present?
      end

      if owner.respond_to?(:shipping_label) && owner.shipping_label&.tracking_number.present?
        return owner.shipping_label.tracking_number
      end

      if owner.respond_to?(:metadata) && owner.metadata.is_a?(Hash) && owner.metadata['delhivery_waybill'].present?
        return owner.metadata['delhivery_waybill']
      end

      nil
    end

    def order_reference_for(owner, order)
      ord_num = (order.respond_to?(:number) ? order.number : nil).presence
      own_num = (owner.respond_to?(:number) ? owner.number : nil).presence
      if own_num.present? && own_num != ord_num
        if ord_num.present? && own_num.start_with?("#{ord_num}-")
          own_num
        else
          [ord_num, own_num].compact.join('-')
        end
      else
        ord_num || own_num || (owner.respond_to?(:id) ? owner.id.to_s : 'DELHIVERY_REF')
      end
    end

    def resolve_destination_address(owner, order, is_return)
      if is_return
        (owner.respond_to?(:ship_from_address) ? owner.ship_from_address : nil) ||
          (order.respond_to?(:ship_address) ? order.ship_address : nil)
      else
        (owner.respond_to?(:address) ? owner.address : nil) ||
          (order.respond_to?(:ship_address) ? order.ship_address : nil)
      end
    end

    def sanitize_phone(phone)
      digits = phone.to_s.gsub(/\D/, '')
      return '' if digits.blank?

      digits.last(10)
    end

    def valid_order_payments(order)
      payments = order.respond_to?(:payments) ? order.payments : []
      if payments.respond_to?(:valid)
        payments.valid
      else
        Array(payments).reject do |p|
          status = p.respond_to?(:status) ? p.status.to_s : ''
          %w[failed invalid void].include?(status)
        end
      end
    end

    def resolve_state_name(record, fallback_country_iso: 'IN')
      return '' if record.nil?

      country_iso = if record.respond_to?(:country) && record.country.respond_to?(:iso)
                      record.country.iso.presence
                    end || fallback_country_iso
      code = record.respond_to?(:state_code) ? record.state_code.to_s.strip.presence : nil

      candidates = []
      candidates << resolve_iso_subdivision_english(country_iso, code) if code.present?
      if record.respond_to?(:state) && record.state.present?
        candidates << record.state.name if record.state.respond_to?(:name)
        code ||= record.state.abbr if record.state.respond_to?(:abbr)
        candidates << resolve_iso_subdivision_english(country_iso, code) if code.present? && candidates.compact.empty?
      end
      candidates << record.state_name if record.respond_to?(:state_name)
      candidates << record.state_name_text if record.respond_to?(:state_name_text)

      ascii = candidates.compact.map { |v| v.to_s.strip }.find { |v| v.present? && v.ascii_only? }
      ascii || candidates.compact.map { |v| v.to_s.strip }.find(&:present?) || code.to_s
    end

    def resolve_iso_subdivision_english(country_iso, state_code)
      return nil unless defined?(ISO3166::Country)

      country = ISO3166::Country.new(country_iso.to_s.upcase)
      sub = country&.subdivisions&.dig(state_code.to_s.upcase)
      return nil if sub.nil?

      translations = sub.respond_to?(:translations) && sub.translations.is_a?(Hash) ? sub.translations : {}
      english = translations[:en] || translations['en']
      return english.to_s.strip if english.present?

      sub.name.to_s.strip if sub.name.to_s.ascii_only?
    rescue StandardError
      nil
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

    def record_booking_ambiguous(owner, ref:)
      return unless owner.respond_to?(:metadata)
      current_meta = owner.metadata.is_a?(Hash) ? owner.metadata.dup : {}
      current_meta['delhivery_booking_state'] = 'requires_reconciliation'
      current_meta['delhivery_booking_ambiguous_at'] = Time.current.iso8601
      current_meta['delhivery_booking_ref'] = ref
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

    def clear_booking_waybill_metadata(owner)
      return unless owner.respond_to?(:metadata)

      current_meta = owner.metadata.is_a?(Hash) ? owner.metadata.dup : {}
      %w[
        delhivery_waybill
        delhivery_booking_ref
        delhivery_upload_wbn
        delhivery_sort_code
        delhivery_booking_state
        delhivery_booking_started_at
      ].each { |key| current_meta.delete(key) }

      if owner.respond_to?(:update_column) && owner.persisted?
        owner.update_column(:metadata, current_meta)
      elsif owner.respond_to?(:metadata=)
        owner.metadata = current_meta
      end
    end

    def build_label_purchase(owner, integration, service_level, waybill, upload_wbn: nil, sort_code: nil)
      pdf_url = integration.client.fetch_packing_slip_url(waybill: waybill)
      selected_rate = owner.respond_to?(:selected_delivery_rate) ? owner.selected_delivery_rate : nil
      order = owner.respond_to?(:order) ? owner.order : nil
      currency = (owner.respond_to?(:store) ? owner.store&.default_currency : nil).presence ||
                 (order.respond_to?(:currency) ? order.currency : nil).presence ||
                 'INR'

      Spree::LabelPurchase.new(
        external_id: waybill,
        carrier: 'Delhivery',
        service: service_level,
        tracking_number: waybill,
        tracking_url: "https://www.delhivery.com/track/package/#{waybill}",
        cost: selected_rate&.cost.to_f,
        currency: currency,
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
      preferred_pickup = integration.respond_to?(:preferred_pickup_location_name) ? integration.preferred_pickup_location_name.to_s.strip.presence : nil
      if e.message.match?(/warehouse|pickup\s*location|clientwarehouse/i) &&
         preferred_pickup.present? &&
         pickup_loc_name != preferred_pickup
        Rails.logger.warn("[Delhivery] Pickup location '#{pickup_loc_name}' rejected by Delhivery. Retrying with master location: #{preferred_pickup}")
        payload[:pickup_location] = { name: preferred_pickup }
        integration.client.create_shipment(payload: payload)
      else
        raise
      end
    end
  end
end
