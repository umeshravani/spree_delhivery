# frozen_string_literal: true

require_relative "lib/spree_delhivery/version"

Gem::Specification.new do |spec|
  spec.name = "spree_delhivery"
  spec.version = SpreeDelhivery::VERSION
  spec.authors = ["Umesh Ravani"]
  spec.email = ["umeshravani98@gmail.com"]
  spec.summary = "Official Delhivery Integration for Spree 5.2+"
  spec.homepage = "https://github.com/yourusername/spree_delhivery"
  spec.license = "BSD-3-Clause"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "spree_core", ">= 5.2.0"
  spec.add_dependency "spree_extension"
  s.add_dependency 'faraday', '>= 2.0'
end
