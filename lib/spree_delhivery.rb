require 'spree_core'
require 'spree_extension'
require 'spree_delhivery/engine'
require 'spree_delhivery/version'
require 'spree_delhivery/configuration'

module SpreeDelhivery
  mattr_accessor :queue

  def self.queue
    @@queue ||= Spree.queues.default
  end
end
