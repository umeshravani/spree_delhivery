namespace :delhivery do
    desc "Fetch available Warehouses from Delhivery"
    task fetch_warehouses: :environment do
      require 'faraday'
      require 'json'
  
      # Load Integration
      integration = Spree::Integrations::Delhivery.active.first
      unless integration
        puts "Error: Delhivery Integration is not active or configured."
        exit
      end
  
      puts "Attempting to Register Warehouse for Token: #{integration.preferred_api_token[0..5]}..."
      
      url = "#{integration.api_url}/api/backend/clientwarehouse/create/"
      
      conn = Faraday.new(url: url) do |c|
        c.headers['Authorization'] = "Token #{integration.preferred_api_token}"
        c.headers['Content-Type'] = 'application/json'
        c.headers['Accept'] = 'application/json'
        c.adapter Faraday.default_adapter
      end
  
      # --- MANDATORY FIELDS ADDED ---
      payload = {
        name: integration.preferred_pickup_location_name,
        address: "2-232/2/A Navrang Tile Studio, Rekurthy", # Using the address from your logs
        pin: "505001",
        phone: "9989147064",
        city: "Karimnagar",
        state: "Telangana",
        country: "India",
        email: "test@example.com", # Optional but good to have
        # Return Address (Mandatory) - Can be same as pickup
        return_address: "2-232/2/A Navrang Tile Studio, Rekurthy",
        return_pin: "505001",
        return_city: "Karimnagar",
        return_state: "Telangana",
        return_country: "India"
      }
  
      puts "Sending Payload: #{payload.to_json}"
      
      response = conn.post('', payload.to_json)
      
      puts "--------------------------------"
      puts "Response Status: #{response.status}"
      puts "Response Body: #{response.body}"
      puts "--------------------------------"
      
      json = JSON.parse(response.body)
      if json['success'] || json['data']&.key?('name')
        puts "✅ Warehouse '#{payload[:name]}' Registered Successfully!"
        puts "👉 You can now go to Admin Panel and click 'Ship with Delhivery'"
      else
        puts "❌ Failed to register warehouse."
      end
    end
  end