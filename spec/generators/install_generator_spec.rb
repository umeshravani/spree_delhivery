# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SpreeDelhivery::Generators::InstallGenerator shipping profile configuration', type: :generator do
  let(:seed_file) { File.expand_path('../../db/seeds.rb', __dir__) }

  before do
    # Define lightweight mock Spree classes if not loaded by host app
    unless defined?(Spree::Store)
      module Spree
        class Store
          attr_accessor :id, :name, :integrations
          def initialize(id: 1, name: 'Default Store')
            @id = id
            @name = name
          end
          def self.all; [new]; end
          def self.default; new; end
          def integrations; @integrations ||= MockRelation.new; end
        end
      end
    end
  end

  describe 'idempotent seeding' do
    it 'defines Surface and Express profiles in seeds' do
      content = File.read(seed_file)
      expect(content).to include("find_or_create_by!(name: 'Delhivery Surface'")
      expect(content).to include("find_or_create_by!(name: 'Delhivery Express'")
      expect(content).to include("code: 'DELHIVERY_SURFACE'")
      expect(content).to include("code: 'DELHIVERY_EXPRESS'")
    end

    it 'executes inside a transaction to prevent partial state' do
      content = File.read(seed_file)
      expect(content).to include('ActiveRecord::Base.transaction do')
    end

    it 'preserves merchant configuration without hardcoding credentials' do
      content = File.read(seed_file)
      expect(content).to include("ENV['DELHIVERY_API_TOKEN']")
      expect(content).not_to match(/preferred_api_token\s*=\s*['"][a-zA-Z0-9_-]{20,}['"]/)
    end

    it 'enables storefront visibility only when properly configured' do
      content = File.read(seed_file)
      expect(content).to include('is_configured = integration.preferred_api_token.present?')
      expect(content).to include('surface_method.storefront_visible = is_configured')
      expect(content).to include('express_method.storefront_visible = is_configured')
    end
  end
end
