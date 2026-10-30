<img width="300" height="auto" alt="Delhivery Header" src="https://github.com/user-attachments/assets/c3fb2919-a732-4719-905a-54d202380703" /><br>

# Spree Delhivery (Spree 6 Commerce)

[![Spree Commerce](https://img.shields.io/badge/Spree-6.0.1-red.svg)](https://spreecommerce.org)
[![Rails Version](https://img.shields.io/badge/Rails-8.1.4-blue.svg)](https://rubyonrails.org)
[![Ruby Version](https://img.shields.io/badge/Ruby-4.0.9-ruby.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An official-grade, beginner-friendly shipping, fulfillment, and Cash on Delivery (COD) extension connecting **[Delhivery](https://www.delhivery.com)** to **Spree Commerce 6**.

Provides real-time shipping rates, automated AWB generation, multi-vendor marketplace routing, a dynamic Cash on Delivery (COD) surcharge via Spree 6 Adjusters, and a live tracking experience for the official Spree Next.js Storefront.

---

## Features

- **Live Shipping Rates**: Real-time rate calculation for **Delhivery Surface** and **Delhivery Express** via Delhivery's Kinko API.
- **Dynamic Cash on Delivery (COD) Surcharge**:
  - Configurable fee in Spree Admin (e.g., ₹90.00).
  - Applied automatically as a native typed line item (`Spree::Fee`, `kind: 'cod'`) via Spree 6's adjusters pipeline (`Spree::Adjusters::DelhiveryCodFee`).
  - Appears dynamically in storefront checkout when COD is selected and disappears when switching to prepaid methods (e.g., Razorpay).
  - Copied cleanly onto completed orders for consistent invoicing.
- **Admin Integrations Gallery**: Registers directly into Spree Admin **Settings $\rightarrow$ Integrations** with official branding (`Spree::ProviderListing`).
- **Encrypted Secrets at Rest**: API token is secured using Rails Active Record encryption (`V-3730`).
- **Automated Fulfillment**: AWB assignment, label generation, and dispatch tracking through Delhivery APIs.
- **Concurrency & Duplicate Booking Protection**: Enforces a 25-second socket timeout and transactional lease coordination to prevent duplicate carrier bookings during network delays or retries.
- **Multi-Vendor Marketplace Support**: Dynamically extracts seller details for Spree 6 split orders (`R10...-1`, `R10...-2`) and matches registered pickup facilities in Delhivery.
- **Zero Database Migrations**: Uses native Spree core tables (`spree_integrations`, `spree_delivery_methods`, `spree_payment_methods`, `spree_fees`).

---

## Compatibility

| Component | Verified Tested Version | Intended Compatibility Range |
|:---|:---|:---|
| **Spree Commerce** | `6.0.1` | `~> 6.0.0` |
| **Ruby on Rails** | `8.1.4` | `>= 7.1.0, < 9.0.0` |
| **Ruby** | `4.0.9` | `>= 3.2.0` |
| **Storefront** | Next.js `16.0.x` | Spree 6 Next.js Storefront (API V3) |

*For complete architectural details, see [docs/compatibility.md](./docs/compatibility.md).*

---

## Quickstart Installation

### With Spree CLI (Docker Starter Projects — Recommended)

```bash
# 1. Add to server/Gemfile
pnpm spree bundle add spree_delhivery --github "umeshravani/spree_delhivery" --branch "spree-6"

# 2. Run the installation generator
pnpm spree rails g spree_delhivery:install

# 3. Restart the Spree development stack
pnpm spree restart
```

### With Standard Rails (Non-Docker)

```bash
# 1. Add to Gemfile
bundle add spree_delhivery --github "umeshravani/spree_delhivery" --branch "spree-6"

# 2. Run the installation generator
bin/rails g spree_delhivery:install

# 3. Restart Rails server
bin/rails restart
```

*For production deployment (Coolify/Docker) and combined installation with Razorpay, see [docs/installation.md](./docs/installation.md).*

---

## Configuration

### 1. Spree Admin Dashboard (Recommended)

1. Open your Spree Admin Dashboard (`/admin` or `http://localhost:5173`).
2. Navigate to **Settings $\rightarrow$ Integrations $\rightarrow$ Delhivery**.
3. Configure your credentials:
   - **API Token**: Your Delhivery production or sandbox API token (stored encrypted).
   - **Client Name**: Your registered Delhivery client name.
   - **Pickup Location**: The registered warehouse/hub name in your Delhivery portal.
   - **COD Surcharge**: Amount to charge for COD orders (e.g. `90.00`). Set to `0` for free COD.
   - **Test Mode**: Checked for staging environments, unchecked for live production.
4. Click **Save Changes**.

### 2. Environment Variables

Alternatively, configure via protected environment variables in your deployment:

```env
DELHIVERY_API_TOKEN=your_production_token
DELHIVERY_PICKUP_LOCATION_NAME=Primary_Warehouse_Delhi
DELHIVERY_CLIENT_NAME=Acme_Retail
DELHIVERY_TEST_MODE=false
DELHIVERY_COD_SURCHARGE=90.00
```

> [!WARNING]
> Always use `DELHIVERY_API_TOKEN` (not `DELHIVERY_API_KEY`) and `DELHIVERY_PICKUP_LOCATION_NAME` (not `DELHIVERY_WAREHOUSE_NAME`).

*For shipping zone setup and concurrency safeguards, see [docs/configuration.md](./docs/configuration.md).*

---

## Next.js Storefront & Tracking Integration

Integrating Delhivery into your Next.js storefront provides:
1. **Dynamic COD Surcharge** displayed in the checkout summary and order confirmation.
2. **Order Tracking Page (`/order/[number]`)** featuring SSR order lookup, live Delhivery scans, and milestone progression.
3. **Tracking Search View (`/order`)** supporting lookup by Order Number, Delhivery AWB, Email, or Phone.

👉 **[Complete Step-by-Step Storefront Guide](./docs/storefront.md)**

---

## Screenshots

| Admin Integrations Gallery | Storefront Live Tracking |
|:---:|:---:|
| ![Delhivery Integration](./docs/assets/screenshots/01-admin-integrations-gallery.png) | ![Live Tracking](./docs/assets/screenshots/07-storefront-order-tracking-timeline.png) |

*For the complete screenshot inventory and masking checklist, see [docs/screenshots.md](./docs/screenshots.md).*

---

## Disabling and Safe Uninstallation

- **To Stop Offering Delhivery Delivery or COD**:
  Simply set **Active** to `No` in Spree Admin (**Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods** or **Settings $\rightarrow$ Payments**). Delhivery methods disappear from checkout immediately. All past orders, shipments, and invoices remain 100% intact.
- **Do NOT delete the gem from `Gemfile` without reviewing [docs/disabling-and-uninstalling.md](./docs/disabling-and-uninstalling.md)**:
  Removing the Ruby gem while historical database records reference `type: 'SpreeDelhivery::Integration'` or `type: 'Spree::PaymentMethod::DelhiveryCod'` causes Rails to raise `ActiveRecord::SubclassNotFound`.

---

## Documentation Index

- [Installation Guide](./docs/installation.md)
- [Configuration Guide](./docs/configuration.md)
- [Next.js Storefront & Order Tracking](./docs/storefront.md)
- [Disabling & Safe Removal](./docs/disabling-and-uninstalling.md)
- [Compatibility Matrix](./docs/compatibility.md)
- [Upgrading Guide](./docs/upgrading.md)
- [Screenshots Checklist & Privacy](./docs/screenshots.md)
- [Changelog](./CHANGELOG.md)

---

## Contributing & License

Bug reports and pull requests are welcome on GitHub.

Spree Delhivery is released under the [MIT License](LICENSE).
