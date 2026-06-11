if defined?(Spree::PageBlock)
  module Spree
    module PageBlocks
      module Products
        class DelhiveryEdd < Spree::PageBlock
          preference :heading_text, :string, default: 'Estimated Delivery Date'
          preference :placeholder_text, :string, default: 'Enter PIN Code'
          preference :button_text, :string, default: 'Check'

          preference :default_mode, :string, default: 'Surface'

          preference :cutoff_time, :string, default: '14:00'
          preference :cutoff_hour, :string, default: '2' 
          preference :cutoff_meridiem, :string, default: 'PM'

          preference :input_border_color, :string, default: '#E2E8F0'
          preference :button_bg_color, :string, default: '#000000'
          preference :button_text_color, :string, default: '#FFFFFF'
          preference :success_color, :string, default: '#10B981'
          preference :error_color, :string, default: '#EF4444'

          def self.block_name
            "Delhivery EDD Widget"
          end

          def self.display_name
            "Delhivery Delivery Checker"
          end

          def icon_name
            "truck-delivery" 
          end

          def render(view_context, locals = {})
            if respond_to?(:available?, true)
              return '' unless available?(locals)
            end
            view_context.render partial: 'spree/page_blocks/products/delhivery_edd/delhivery_edd',
                                locals: locals.merge(block: self)
          end
        end
      end
    end
  end
end
