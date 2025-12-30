module SpreeDelhivery
  class BaseJob < Spree::BaseJob
    queue_as SpreeDelhivery.queue
  end
end
