module Spree
    module Admin
      module StockLocationsControllerDecorator
        def delhivery_pickup
          @stock_location = Spree::StockLocation.find(params[:id])
          
          # 1. Capture Params
          count = params[:count].to_i
          count = 1 if count <= 0
          
          date = params[:pickup_date] # Format: "YYYY-MM-DD" from HTML5 input
          time = params[:pickup_time] # Format: "HH:MM"
  
          # 2. Call Service
          # passing the named arguments your service expects
          service = SpreeDelhivery::PickupService.new(
            @stock_location, 
            date: date, 
            time: time, 
            count: count
          )
          
          result = service.call
  
          # 3. Handle Result
          if result.success?
            flash[:success] = result.message
          else
            flash[:error] = "Delhivery Error: #{result.message}"
          end
  
          redirect_to edit_admin_stock_location_path(@stock_location)
        end
      end
    end
  end
  
  Spree::Admin::StockLocationsController.prepend(Spree::Admin::StockLocationsControllerDecorator)