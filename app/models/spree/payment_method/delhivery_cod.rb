module Spree
    class PaymentMethod::DelhiveryCod < PaymentMethod
      def actions
        %w{capture void}
      end
  
      # COD payments are usually not captured automatically
      def auto_capture?
        false
      end
  
      def method_type
        'delhivery_cod'
      end
  
      def source_required?
        false
      end
      
      # Required for Spree 5.4 Admin UI
      def partial_name
        'delhivery_cod'
      end
    end
  end
