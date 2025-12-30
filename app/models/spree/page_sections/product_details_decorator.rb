module Spree
    module PageSections
      module ProductDetailsDecorator
        def default_blocks
          super + [
            Spree::PageBlocks::Products::RazorpayAffordability.new,
            Spree::PageBlocks::Products::DelhiveryEdd.new # Added this
          ]
        end
  
        def available_blocks_to_add
          super + [
            Spree::PageBlocks::Products::RazorpayAffordability,
            Spree::PageBlocks::Products::DelhiveryEdd # Added this
          ]
        end
      end
    end
  end
  
  Spree::PageSections::ProductDetails.prepend(Spree::PageSections::ProductDetailsDecorator)