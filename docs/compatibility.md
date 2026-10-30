# Compatibility Matrix

This document defines the supported runtime environments and architectural compatibility for **Spree Delhivery**.

---

## Supported Versions

| Component | Verified Tested Version | Supported / Intended Range | Notes |
|:---|:---|:---|:---|
| **Spree Commerce** | `6.0.1` | `~> 6.0.0` | Tested on Spree `6.0.0` and `6.0.1`. |
| **Ruby on Rails** | `8.1.4` | `>= 7.1.0, < 9.0.0` | Uses Rails 8 Active Record encryption (`V-3730`). |
| **Ruby** | `4.0.9` | `>= 3.2.0` | Full compatibility with modern YJIT Ruby. |
| **Faraday** | `2.12.x` | `~> 2.0` | Used for live rate calculation and tracking requests. |
| **Spree Storefront** | Next.js `16.0.x` | Next.js App Router | Uses `@spree/sdk` API V3 endpoints. |

---

## Architectural Evolutions: Spree 5 vs Spree 6

Spree 6 introduced significant architectural changes to fulfillment, checkout, and pricing models:

### 1. Adjusters Pipeline vs Legacy Adjustments
- **Spree 5**: Surcharges were created as polymorphic `Spree::Adjustment` records attached to shipments or orders, updated via state-machine callbacks.
- **Spree 6**: Spree 6 eliminated generic adjustments in favor of strongly-typed money rows: `Spree::TaxLine`, `Spree::Discount`, and `Spree::Fee`. Spree Delhivery implements `Spree::Adjusters::DelhiveryCodFee < Spree::Adjusters::Base` which dynamically creates and updates `Spree::Fee(kind: 'cod')` rows during `Spree::Carts::RecalculateTotals`.

### 2. Cart $\rightarrow$ Order Split & Fulfillments
- **Spree 5**: Single `Spree::Order` model moving through state machine steps (`address` $\rightarrow$ `delivery` $\rightarrow$ `payment` $\rightarrow$ `confirm` $\rightarrow$ `complete`).
- **Spree 6**: Clear separation between `Spree::Cart` (in-flight shopping) and `Spree::Order` (immutable completed record). The completion workflow (`Spree::Carts::Complete`) safely copies typed fee lines and seals the order.

### 3. Native Integration & Provider Registry
- **Spree 5**: Custom payment and delivery providers were registered in `Rails.application.config.spree.payment_methods` and required custom defaced ERB views in the admin.
- **Spree 6**: Integrations register via `Spree::ProviderListing` and appear automatically in the React Admin Dashboard (`Settings $\rightarrow$ Integrations`), with encrypted credentials handled by Rails Active Record encryption.

---

## Database Schema & Migrations

**Spree Delhivery requires 0 custom database migrations.**

All data models utilize native Spree 6 core tables:
- `spree_integrations`: Stores carrier configuration and encrypted tokens.
- `spree_delivery_methods`: Stores Express and Surface shipping methods.
- `spree_payment_methods`: Stores the COD payment method.
- `spree_fees`: Stores dynamic COD surcharges on carts and completed orders.

