# Disabling and Safe Uninstallation

This document explains how to safely disable **Spree Delhivery** via the Spree Admin Dashboard and outlines the technical risks and constraints of experimental gem removal.

---

## 1. Recommended Safe Procedure: Dashboard Deactivation

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

### Why Dashboard Deactivation is the Only Recommended Approach:
- **Zero Downtime**: Changes take effect immediately without requiring application rebuilds or deployments.
- **Historical Integrity**: Completed orders, customer receipts, and past delivery waybills retain their full historical data.
- **No STI Crashes**: Existing records in database tables continue to load cleanly.

---

## 2. The Rails Single Table Inheritance (STI) Hazard

Spree Delhivery stores Ruby class names in Spree core Single Table Inheritance (STI) tables:

| Table | Column | Stored Ruby Class |
|:---|:---|:---|
| `spree_payment_methods` | `type` | `Spree::PaymentMethod::DelhiveryCod` |
| `spree_integrations` | `type` | `SpreeDelhivery::Integration` |
| `spree_fees` | `kind` | `cod` |

### What Happens If You Delete the Gem from `Gemfile`?

If you delete `gem 'spree_delhivery'` from `server/Gemfile` while historical records exist in `spree_payment_methods` or `spree_integrations`:

1. Rails boots without defining the classes `Spree::PaymentMethod::DelhiveryCod` or `SpreeDelhivery::Integration`.
2. When staff visit the Payments, Shipping, Integrations, or Orders pages in Spree Admin, Active Record queries these tables.
3. Active Record attempts to instantiate each row by constantizing the class name in the `type` column.
4. Rails crashes with:
   ```text
   ActiveRecord::SubclassNotFound:
     The single-table inheritance mechanism failed to locate the subclass: 'SpreeDelhivery::Integration'.
   ```
   or
   ```text
   ActiveRecord::SubclassNotFound:
     The single-table inheritance mechanism failed to locate the subclass: 'Spree::PaymentMethod::DelhiveryCod'.
   ```

### Never Delete or Retype Historical Financial Records
Never execute SQL queries deleting payment or fulfillment records or reassigning `spree_payment_methods.type` or `spree_integrations.type`.
- It falsifies cash collection records for past Cash on Delivery shipments.
- It destroys carrier tracking numbers, packing slip links, and fulfillment audit records on customer orders.
- It breaks financial reconciliation between order totals and bank deposits.

---

## 3. Advanced & Experimental: Code Removal Compatibility Shim

> [!WARNING]
> **Unsupported for Production Stores with Historical Orders or Fulfillments**
> Complete gem uninstallation is NOT recommended if your store has processed real shipments or COD orders. While a minimal Ruby class shim prevents immediate `ActiveRecord::SubclassNotFound` errors when loading simple records, fulfillment tracking updates, carrier re-checks, and background jobs will fail with `NoMethodError` because the gem's service objects and clients are no longer loaded.
>
> Dashboard deactivation (Section 1) is the only fully tested, supported, and zero-risk procedure.

If you are running an experimental or non-production environment where the gem must be pruned from `Gemfile`, define empty class shims in your host application:

**File:** `server/config/initializers/spree_delhivery_shim.rb`

```ruby
# frozen_string_literal: true

# Advanced/Experimental: Allows basic Active Record loading when spree_delhivery is removed.
# Note: Runtime methods (tracking lookups, rate calculation, fulfillment) are NOT functional.
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

### Limitations of the Compatibility Shim:
1. **No Live Tracking Updates**: Attempting to sync or refresh carrier tracking on historical shipments will fail.
2. **No Packing Slip Downloads**: PDF waybill links cannot be regenerated.
3. **Read-Only Inspection Only**: The shim is strictly suitable for basic display of past orders.
