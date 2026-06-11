module Spree
  module PageSections
    module ProductDetailsDecorator
      def default_blocks
        # Safely add blocks only if they are loaded into memory
        blocks = super
        blocks << Spree::PageBlocks::Products::RazorpayAffordability.new if defined?(Spree::PageBlocks::Products::RazorpayAffordability)
        blocks << Spree::PageBlocks::Products::DelhiveryEdd.new if defined?(Spree::PageBlocks::Products::DelhiveryEdd)
        blocks
      end

      def available_blocks_to_add
        blocks = super
        blocks << Spree::PageBlocks::Products::RazorpayAffordability if defined?(Spree::PageBlocks::Products::RazorpayAffordability)
        blocks << Spree::PageBlocks::Products::DelhiveryEdd if defined?(Spree::PageBlocks::Products::DelhiveryEdd)
        blocks
      end
    end
  end
end

# ONLY prepend if the core Storefront class exists. 
# This sits OUTSIDE the module definition.
if defined?(Spree::PageSections::ProductDetails)
  Spree::PageSections::ProductDetails.prepend(Spree::PageSections::ProductDetailsDecorator)
end
