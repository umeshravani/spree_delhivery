# frozen_string_literal: true

namespace :spree_delhivery do
  desc 'Seed Delhivery Delivery Profile, Delivery Methods, and COD Payment Method'
  task seeds: :environment do
    seed_file = File.expand_path('../../db/seeds.rb', __dir__)
    if File.exist?(seed_file)
      load(seed_file)
    else
      puts "Seed file not found at #{seed_file}"
    end
  end

  desc 'Install Spree Delhivery plugin and seed default data'
  task install: :seeds
end
