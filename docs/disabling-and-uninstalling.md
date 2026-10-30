# Disabling and Safe Uninstallation

This document explains how to safely disable **Spree Delhivery** and outlines the technical risks and mitigation steps if permanently removing the gem.

---

## 1. Safe Disabling (Recommended)

If you wish to temporarily or permanently stop offering Delhivery delivery methods or Cash on Delivery (COD) to customers, **do NOT delete the gem from your `Gemfile`**.

Instead, disable the integration and methods via the Spree Admin Dashboard:

### Disabling COD Payment Method
1. Navigate to Spree Admin $\rightarrow$ **Settings $\rightarrow$ Payments**.
2. Select **Cash on Delivery (Delhivery COD)**.
3. Toggle:
   - **Active**: `No`
   - **Storefront Visible**: `No`
4. Click **Save Changes**.

### Disabling Delivery Methods
1. Navigate to Spree Admin $\rightarrow$ **Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods**.
2. Select **Delhivery Express** and set **Active** / **Storefront Visible** to `No`.
3. Select **Delhivery Surface** and set **Active** / **Storefront Visible** to `No`.

### Disabling Carrier Integration
1. Navigate to Spree Admin $\rightarrow$ **Settings $\rightarrow$ Integrations $\rightarrow$ Delhivery**.
2. Set **Active** to `No` and click **Save Changes**.

### Why Disabling is the Recommended Approach:
- **Zero Downtime**: Changes take effect immediately without requiring application rebuilds or deployments.
- **Historical Integrity**: Completed orders, customer receipts, and past delivery waybills retain their full historical data.
- **No STI Crashes**: Existing records in database tables continue to load cleanly.

---

## 2. The Rails Single Table Inheritance (STI) Hazard

Like official Spree payment and delivery providers, Spree Delhivery uses Rails Single Table Inheritance (STI):

| Table | Column | Stored Ruby Class |
|:---|:---|:---|
| `spree_payment_methods` | `type` | `Spree::PaymentMethod::DelhiveryCod` |
| `spree_integrations` | `type` | `SpreeDelhivery::Integration` |
| `spree_fees` | `kind` | `cod` |

### What Happens If You Delete the Gem from `Gemfile`?

If you delete `gem 'spree_delhivery'` from `server/Gemfile` while historical records exist in `spree_payment_methods` or `spree_integrations`:

1. Rails boots without defining the classes `Spree::PaymentMethod::DelhiveryCod` or `SpreeDelhivery::Integration`.
2. When the Spree Admin visits the Payments, Integrations, or Orders pages, Active Record runs `SELECT * FROM spree_payment_methods` or `SELECT * FROM spree_integrations`.
3. Active Record attempts to instantiate each row by constantizing the class name in the `type` column.
4. Rails crashes with:
   ```
   ActiveRecord::SubclassNotFound:
     The single-table inheritance mechanism failed to locate the subclass: 'SpreeDelhivery::Integration'.
     Make sure the subclass is defined and exists in your code.
   ```
   or
   ```
   ActiveRecord::SubclassNotFound:
     The single-table inheritance mechanism failed to locate the subclass: 'Spree::PaymentMethod::DelhiveryCod'.
   ```

This crash prevents staff from managing any orders or settings in the Admin Dashboard.

---

## 3. Safe Uninstallation Procedure (Permanent Gem Removal)

If you must permanently remove the gem from your codebase, you must either sanitize historical database records or install a lightweight compatibility shim.

### Option A: Compatibility Shim (Preserves Historical Data)

Before or immediately after removing the gem from `Gemfile`, create a lightweight fallback shim in your Rails app:

**File:** `server/config/initializers/spree_delhivery_shim.rb`

```ruby
# frozen_string_literal: true

# Preserves historical records when spree_delhivery gem is removed.
unless defined?(SpreeDelhivery::Integration)
  module SpreeDelhivery
    class Integration < Spree::Integration
    end
  end
end

unless defined?(Spree::PaymentMethod::DelhiveryCod)
  module Spree
    class PaymentMethod < Spree::Base
      class DelhiveryCod < Spree::PaymentMethod
      end
    end
  end
end
```

This prevents `ActiveRecord::SubclassNotFound` while allowing you to safely remove `spree_delhivery` from `Gemfile`.

---

### Option B: Database Record Sanitization

If you prefer not to maintain a shim and have verified that historical data can be archived:

1. Deactivate all Delhivery methods and integrations.
2. In Rails console:
   ```ruby
   # Archive or nullify historical method references
   Spree::PaymentMethod.where(type: 'Spree::PaymentMethod::DelhiveryCod').update_all(active: false, storefront_visible: false)
   Spree::Integration.where(type: 'SpreeDelhivery::Integration').destroy_all
   ```
3. Remove `spree_delhivery` from `server/Gemfile`.
4. Run `pnpm spree bundle lock` and restart the application.
