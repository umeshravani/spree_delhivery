module SpreeDelhivery
  class TrackerEvent
    attr_reader :payload

    def initialize(payload)
      @payload = payload
    end

    def self.from_webhook(parsed_json)
      new(parsed_json)
    end

    def to_update_tracking_arguments
      status = map_status(payload.dig('Shipment', 'Status', 'Status'))
      
      {
        tracking_code: payload.dig('Shipment', 'AWB'),
        tracking_status: status,
        delivered_at: status == 'delivered' ? Time.current : nil,
        details: payload.dig('Shipment', 'Status', 'StatusLocation')
      }
    end

    private

    def map_status(delhivery_status)
      case delhivery_status
      when 'Dispatched', 'In Transit'
        'in_transit'
      when 'Out for Delivery'
        'out_for_delivery'
      when 'Delivered'
        'delivered'
      when 'RTO'
        'return_to_sender'
      when 'Cancelled'
        'failure'
      else
        'in_transit'
      end
    end
  end
end
