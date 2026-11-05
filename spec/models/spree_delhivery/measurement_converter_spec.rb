# frozen_string_literal: true

require 'spec_helper'
require 'spree_delhivery'
require File.expand_path('../../../app/models/spree_delhivery/measurement_converter', __dir__)
require 'ostruct'

RSpec.describe SpreeDelhivery::MeasurementConverter do
  describe '.to_centimeters' do
    it 'converts inches to centimeters (12 in -> 30.48 cm)' do
      expect(described_class.to_centimeters(12, unit: 'in')).to eq(30.48)
      expect(described_class.to_centimeters(12, unit: 'inch')).to eq(30.48)
      expect(described_class.to_centimeters(12, unit: 'inches')).to eq(30.48)
    end

    it 'converts inches to centimeters (24 in -> 60.96 cm)' do
      expect(described_class.to_centimeters(24, unit: 'in')).to eq(60.96)
    end

    it 'converts inches to centimeters (2 in -> 5.08 cm)' do
      expect(described_class.to_centimeters(2, unit: 'in')).to eq(5.08)
    end

    it 'converts millimeters to centimeters (100 mm -> 10.0 cm)' do
      expect(described_class.to_centimeters(100, unit: 'mm')).to eq(10.0)
    end

    it 'converts meters to centimeters (1.5 m -> 150.0 cm)' do
      expect(described_class.to_centimeters(1.5, unit: 'm')).to eq(150.0)
    end

    it 'converts feet to centimeters (1 ft -> 30.48 cm)' do
      expect(described_class.to_centimeters(1, unit: 'ft')).to eq(30.48)
    end

    it 'passes through centimeters (25 cm -> 25.0 cm)' do
      expect(described_class.to_centimeters(25, unit: 'cm')).to eq(25.0)
    end

    it 'falls back to default dimension for non-positive values' do
      expect(described_class.to_centimeters(0, unit: 'in')).to eq(10.0)
      expect(described_class.to_centimeters(-5, unit: 'cm')).to eq(10.0)
    end
  end

  describe '.to_grams' do
    it 'converts kilograms to grams (4 kg -> 4000.0 g)' do
      expect(described_class.to_grams(4, unit: 'kg')).to eq(4000.0)
      expect(described_class.to_grams(4, unit: 'kilogram')).to eq(4000.0)
      expect(described_class.to_grams(4, unit: 'kilograms')).to eq(4000.0)
      expect(described_class.to_grams(4, unit: 'kgs')).to eq(4000.0)
    end

    it 'converts pounds to grams (1 lb -> 453.59 g)' do
      expect(described_class.to_grams(1, unit: 'lb')).to eq(453.59)
      expect(described_class.to_grams(1, unit: 'lbs')).to eq(453.59)
    end

    it 'converts ounces to grams (1 oz -> 28.35 g)' do
      expect(described_class.to_grams(1, unit: 'oz')).to eq(28.35)
    end

    it 'passes through grams (500 g -> 500.0 g)' do
      expect(described_class.to_grams(500, unit: 'g')).to eq(500.0)
      expect(described_class.to_grams(500, unit: 'gm')).to eq(500.0)
    end

    it 'preserves exact weight for items below minimum package weight' do
      expect(described_class.to_grams(10, unit: 'g')).to eq(10.0)
    end

    it 'falls back to default weight for non-positive values' do
      expect(described_class.to_grams(0, unit: 'kg')).to eq(500.0)
      expect(described_class.to_grams(-2, unit: 'lb')).to eq(500.0)
    end
  end

  describe '.volumetric_weight_in_grams' do
    it 'calculates volumetric weight in grams using Delhivery formula' do
      # L: 30.48 cm, W: 60.96 cm, H: 5.08 cm -> Volume = 9439.117 cm^3
      # Delhivery formula: volume / 5.0 -> 1887.82 grams
      expected = ((30.48 * 60.96 * 5.08) / 5.0).round(2)
      expect(described_class.volumetric_weight_in_grams(30.48, 60.96, 5.08)).to eq(expected)
    end
  end

  describe '.package_dimensions_in_cm and .chargeable_weight_in_grams' do
    let(:variant) do
      OpenStruct.new(
        depth: 2,
        width: 24,
        height: 12,
        dimensions_unit: 'in',
        weight: 4,
        weight_unit: 'kg'
      )
    end

    let(:line_item) do
      OpenStruct.new(
        variant: variant,
        quantity: 1
      )
    end

    let(:package) do
      OpenStruct.new(
        contents: [line_item],
        store: OpenStruct.new(preferred_weight_unit: 'kg', preferred_dimension_unit: 'in')
      )
    end

    it 'converts variant dimensions (12 in height, 24 in width, 2 in depth) to cm' do
      length_cm, width_cm, height_cm = described_class.package_dimensions_in_cm(package)
      # Depth 2 in -> 5.08 cm -> ceil 6
      expect(length_cm).to eq(6)
      # Width 24 in -> 60.96 cm -> ceil 61
      expect(width_cm).to eq(61)
      # Height 12 in -> 30.48 cm -> ceil 31
      expect(height_cm).to eq(31)
    end

    it 'computes dead weight in grams (4 kg -> 4000 g)' do
      dead_weight = described_class.package_dead_weight_in_grams(package)
      expect(dead_weight).to eq(4000)
    end

    it 'enforces minimum package weight of 50g for lightweight items' do
      tiny_package = OpenStruct.new(
        contents: [OpenStruct.new(variant: OpenStruct.new(weight: 10, weight_unit: 'g'), quantity: 1)]
      )
      expect(described_class.package_dead_weight_in_grams(tiny_package)).to eq(50)
    end

    it 'computes chargeable weight as max(dead_weight, volumetric_weight)' do
      # Dead weight = 4000g
      # Volumetric weight = (6 * 61 * 31) / 5.0 = 11346 / 5.0 = 2269.2g
      # Max is 4000g
      expect(described_class.chargeable_weight_in_grams(package)).to eq(4000)
    end
  end
end
