# frozen_string_literal: true

module SpreeDelhivery
  module MeasurementConverter
    DEFAULT_DIMENSION_CM = 10.0
    DEFAULT_WEIGHT_GRAMS = 500.0
    MIN_WEIGHT_GRAMS = 50.0
    MIN_DIMENSION_CM = 1.0

    class << self
      # Normalizes length values into centimeters (cm)
      # Supports: mm, cm, m, in/inch, ft/feet
      def to_centimeters(value, unit: 'cm')
        val = value.to_f
        return DEFAULT_DIMENSION_CM if val <= 0

        norm_unit = unit.to_s.strip.downcase.presence || 'cm'

        cm = case norm_unit
             when 'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'
               val / 10.0
             when 'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'
               val
             when 'm', 'meter', 'meters', 'metre', 'metres'
               val * 100.0
             when 'in', 'inch', 'inches', '"'
               val * 2.54
             when 'ft', 'foot', 'feet', "'"
               val * 30.48
             else
               if defined?(Spree::Measurement)
                 Spree::Measurement.to_centimeters(val, unit: norm_unit).to_f rescue val
               else
                 val
               end
             end

        [cm.to_f.round(2), MIN_DIMENSION_CM].max
      end

      # Normalizes weight values into grams (g)
      # Supports: g/gm, kg, lb/lbs, oz
      def to_grams(value, unit: 'g')
        val = value.to_f
        return DEFAULT_WEIGHT_GRAMS if val <= 0

        norm_unit = unit.to_s.strip.downcase.presence || 'g'

        grams = case norm_unit
                when 'g', 'gram', 'grams', 'gm', 'gms'
                  val
                when 'kg', 'kilogram', 'kilograms', 'kgs'
                  val * 1000.0
                when 'lb', 'lbs', 'pound', 'pounds'
                  val * 453.59237
                when 'oz', 'ounce', 'ounces'
                  val * 28.349523
                else
                  if defined?(Spree::Measurement)
                    Spree::Measurement.convert_weight(val, from: norm_unit, to: 'g').to_f rescue val
                  else
                    val
                  end
                end

        [grams.to_f.round(2), MIN_WEIGHT_GRAMS].max
      end

      # Computes dead weight in grams for an entire package or fulfillment
      def package_dead_weight_in_grams(package)
        store = extract_store(package)
        default_wt_unit = store_weight_unit(store)

        items = extract_items(package)
        if items.empty?
          raw_wt = package.respond_to?(:weight) ? package.weight.to_f : 0.0
          return to_grams(raw_wt > 0 ? raw_wt : DEFAULT_WEIGHT_GRAMS, unit: default_wt_unit).to_i
        end

        total_grams = items.sum do |item|
          qty = (item.respond_to?(:quantity) ? item.quantity : 1).to_i
          qty = 1 if qty <= 0
          variant = item.respond_to?(:variant) ? item.variant : nil

          raw_wt = variant&.weight.to_f
          unit = variant&.weight_unit.presence || default_wt_unit

          item_grams = raw_wt > 0 ? to_grams(raw_wt, unit: unit) : 0.0
          item_grams * qty
        end

        if total_grams <= 0
          raw_wt = package.respond_to?(:weight) ? package.weight.to_f : 0.0
          total_grams = raw_wt > 0 ? to_grams(raw_wt, unit: default_wt_unit) : DEFAULT_WEIGHT_GRAMS
        end

        [total_grams.round, MIN_WEIGHT_GRAMS.to_i].max
      end

      # Computes dimensions [length_cm, width_cm, height_cm] for a package or fulfillment.
      # Returns [length, width, height] in centimeters, where:
      # - length_cm: variant.depth converted to cm
      # - width_cm:  variant.width converted to cm
      # - height_cm: variant.height converted to cm
      def package_dimensions_in_cm(package)
        store = extract_store(package)
        default_dim_unit = store_dimension_unit(store)

        items = extract_items(package)
        if items.empty?
          return [DEFAULT_DIMENSION_CM.ceil, DEFAULT_DIMENSION_CM.ceil, DEFAULT_DIMENSION_CM.ceil]
        end

        item_dims = items.map do |item|
          variant = item.respond_to?(:variant) ? item.variant : nil
          unit = variant&.dimensions_unit.presence || default_dim_unit

          d_raw = variant&.depth.to_f
          w_raw = variant&.width.to_f
          h_raw = variant&.height.to_f

          d = d_raw > 0 ? to_centimeters(d_raw, unit: unit) : nil
          w = w_raw > 0 ? to_centimeters(w_raw, unit: unit) : nil
          h = h_raw > 0 ? to_centimeters(h_raw, unit: unit) : nil

          {
            depth: d,
            width: w,
            height: h,
            quantity: (item.respond_to?(:quantity) ? item.quantity : 1).to_i
          }
        end

        valid_depths  = item_dims.filter_map { |d| d[:depth] }
        valid_widths  = item_dims.filter_map { |d| d[:width] }
        valid_heights = item_dims.filter_map { |d| d[:height] }

        max_length = valid_depths.max
        max_width  = valid_widths.max
        max_height = valid_heights.max

        if max_length.nil? || max_width.nil? || max_height.nil?
          pkg_dims = package.respond_to?(:dimensions) ? (package.dimensions rescue nil) : nil
          if pkg_dims.is_a?(Hash)
            max_length ||= to_centimeters(pkg_dims[:length] || pkg_dims[:depth] || DEFAULT_DIMENSION_CM, unit: default_dim_unit)
            max_width  ||= to_centimeters(pkg_dims[:width] || DEFAULT_DIMENSION_CM, unit: default_dim_unit)
            max_height ||= to_centimeters(pkg_dims[:height] || DEFAULT_DIMENSION_CM, unit: default_dim_unit)
          end
        end

        max_length ||= DEFAULT_DIMENSION_CM
        max_width  ||= DEFAULT_DIMENSION_CM
        max_height ||= DEFAULT_DIMENSION_CM

        [
          [max_length.ceil, MIN_DIMENSION_CM.to_i].max,
          [max_width.ceil, MIN_DIMENSION_CM.to_i].max,
          [max_height.ceil, MIN_DIMENSION_CM.to_i].max
        ]
      end

      # Computes volumetric weight in grams using Delhivery formula:
      # (L * W * H in cm) / 5000 (kg) -> in grams (* 1000) = (L * W * H) / 5.0
      def volumetric_weight_in_grams(length_cm, width_cm, height_cm)
        volume_cm3 = length_cm.to_f * width_cm.to_f * height_cm.to_f
        (volume_cm3 / 5.0).round(2)
      end

      # Computes chargeable weight in grams: max(dead_weight, volumetric_weight)
      def chargeable_weight_in_grams(package)
        dead_weight = package_dead_weight_in_grams(package)
        length_cm, width_cm, height_cm = package_dimensions_in_cm(package)
        vol_weight = volumetric_weight_in_grams(length_cm, width_cm, height_cm)

        [[dead_weight, vol_weight].max.ceil, MIN_WEIGHT_GRAMS.to_i].max
      end

      private

      def extract_store(package)
        package.try(:store) ||
          package.try(:owner)&.try(:store) ||
          package.try(:order)&.try(:store) ||
          (Spree::Current.store rescue nil) ||
          (Spree::Store.default rescue nil)
      end

      def store_weight_unit(store)
        (store.respond_to?(:preferred_weight_unit) && store.preferred_weight_unit.presence) || 'g'
      end

      def store_dimension_unit(store)
        if store.respond_to?(:preferred_dimension_unit) && store.preferred_dimension_unit.presence
          store.preferred_dimension_unit
        elsif store.respond_to?(:metric_unit_system?)
          store.metric_unit_system? ? 'cm' : 'in'
        else
          'cm'
        end
      end

      def extract_items(package)
        if package.respond_to?(:contents) && package.contents.present?
          package.contents.to_a
        elsif package.respond_to?(:fulfillment_items) && package.fulfillment_items.present?
          package.fulfillment_items.to_a
        elsif package.respond_to?(:line_items) && package.line_items.present?
          package.line_items.to_a
        elsif package.respond_to?(:inventory_units) && package.inventory_units.present?
          package.inventory_units.to_a
        elsif package.is_a?(Array)
          package
        else
          []
        end
      end
    end
  end
end
