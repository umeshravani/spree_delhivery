module SpreeDelhivery
    class PickupService
      Result = Struct.new(:success?, :message, :data)
  
      def initialize(stock_location, date: nil, time: "16:00:00", count: 1)
        @stock_location = stock_location
        @date = date || Date.tomorrow.strftime('%Y-%m-%d')
        @time = time
        @count = count
        @client = SpreeDelhivery::Client.new
      end
  
      def call
        # 1. Validation
        unless @stock_location.delhivery_warehouse_name.present?
          return Result.new(false, "Stock Location is missing Warehouse Name.")
        end
  
        # 2. Call API
        begin
          response = @client.create_pickup_request(
            location_name: @stock_location.delhivery_warehouse_name,
            date: @date,
            time: @time,
            count: @count
          )
  
          # --- [DEBUG] START: Add this line ---
          puts "\n\n🔴 [DELHIVERY DEBUG] RAW RESPONSE: #{response.inspect}\n\n"
          # --- [DEBUG] END ---
  
          # 3. Parse Response
          if response['pickup_id'].present?
            return Result.new(true, "Pickup Scheduled! ID: #{response['pickup_id']}", response)
          elsif response['error'].present?
            return Result.new(false, response['error'])
          else
            # Fallback
            msg = response['pre_feed_back'] || "Unknown Response: #{response}"
            return Result.new(false, msg)
          end
  
        rescue StandardError => e
          Rails.logger.error "[Delhivery] Pickup Error: #{e.message}"
          return Result.new(false, e.message)
        end
      end
    end
  end