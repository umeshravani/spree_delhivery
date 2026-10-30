# Installing Spree Delhivery

This guide explains how to install and seed the **Spree Delhivery** extension in any Spree Commerce 6 application.

---

## Prerequisites

Before installing, ensure your environment meets the minimum version requirements:

- **Spree Commerce**: `6.0.0` or `6.0.1` (tested and verified on `6.0.1`)
- **Ruby on Rails**: `8.1.x` (or `>= 7.1.0`)
- **Ruby**: `>= 3.2.0` (tested on Ruby `4.0.9`)
- **Spree Next.js Storefront** (optional, for customer-facing checkout & tracking)

---

## Installation Methods

### Method 1: Spree CLI (Docker Starter Projects — Recommended)

If you created your store using the standard Spree starter or CLI (`@spree/cli`):

```bash
# 1. Add gem to server/Gemfile
pnpm spree bundle add spree_delhivery --github "umeshravani/spree_delhivery" --branch "spree-6"

# 2. Run the installation generator
pnpm spree rails g spree_delhivery:install

# 3. Restart the Spree development stack
pnpm spree restart
```

---

### Method 2: Standard Rails (Non-Docker / Native)

If you are running Rails directly on your host or in a custom container:

```bash
# 1. Add gem to your Gemfile
bundle add spree_delhivery --github "umeshravani/spree_delhivery" --branch "spree-6"

# 2. Run the installation generator
bin/rails g spree_delhivery:install

# 3. Restart Rails
bin/rails restart
```

---

### Method 3: Production Docker / Coolify Deployment

For containerized production environments:

1. Add the pinned gem to `server/Gemfile`:
   ```ruby
   gem 'spree_delhivery', github: 'umeshravani/spree_delhivery', branch: 'spree-6'
   ```

2. Run `bundle lock` inside the build context to update `server/Gemfile.lock`:
   ```bash
   pnpm spree bundle lock
   ```

3. Ensure production environment variables are configured in Coolify or your Docker Compose file:
   ```yaml
   environment:
     - DELHIVERY_API_TOKEN=your_live_token
     - DELHIVERY_PICKUP_LOCATION_NAME=Primary_Warehouse
     - DELHIVERY_CLIENT_NAME=Acme_Retail
     - DELHIVERY_TEST_MODE=false
     - DELHIVERY_COD_SURCHARGE=90.00
   ```

4. During post-deployment release phase or one-time container run, execute the seeds:
   ```bash
   pnpm spree rails spree_delhivery:seeds
   ```

---

## Combined Installation with Spree Razorpay

`spree_delhivery` and `spree_razorpay` are engineered to operate together seamlessly in an Indian e-commerce checkout. Delhivery handles shipping calculations, AWB fulfillment, and Cash on Delivery (COD); Razorpay handles instant prepaid payments (UPI, Cards, NetBanking).

To install both in a single step:

```bash
# Add both gems
pnpm spree bundle add spree_delhivery --github "umeshravani/spree_delhivery" --branch "spree-6"
pnpm spree bundle add spree_razorpay --github "umeshravani/spree_razorpay" --branch "spree-6"

# Run both generators
pnpm spree rails g spree_delhivery:install
pnpm spree rails g spree_razorpay:install

# Restart services
pnpm spree restart
```

When both are installed:
- Selecting **Cash on Delivery** automatically attaches the configured `COD Surcharge` fee (e.g. ₹90.00).
- Selecting **Razorpay** instantly recalculates cart totals and removes the COD fee.

---

## What the Installation Generator Does

The `rails g spree_delhivery:install` generator:

1. **Creates Delivery Profile**:
   - `Delhivery` (`Spree::DeliveryProfiles::Shipping`)
2. **Creates Delivery Methods**:
   - `Delhivery Express` (Rate Provider: `Delhivery`, Fulfillment Provider: `Delhivery`)
   - `Delhivery Surface` (Rate Provider: `Delhivery`, Fulfillment Provider: `Delhivery`)
3. **Creates Payment Method**:
   - `Cash on Delivery (Delhivery COD)` (`Spree::PaymentMethod::DelhiveryCod`)
4. **Registers COD Adjuster**:
   - `Spree::Adjusters::DelhiveryCodFee` in `Spree.adjusters`
5. **Zero Database Migrations**:
   - No custom tables or schema changes are added. All settings and records use Spree 6 standard STI tables (`spree_delivery_methods`, `spree_payment_methods`, `spree_integrations`, `spree_fees`).

---

## Verification

After installation, verify that the plugin registered correctly:

### Via Rails Console:
```bash
pnpm spree console
```
```ruby
# 1. Verify Integration Registration
Spree::Integration.available_providers.include?('Delhivery') # => true

# 2. Verify Delivery Methods
Spree::DeliveryMethod.where(fulfillment_provider: 'Delhivery').pluck(:name)
# => ["Delhivery Express", "Delhivery Surface"]

# 3. Verify COD Payment Method
Spree::PaymentMethod.find_by(type: 'Spree::PaymentMethod::DelhiveryCod').present? # => true

# 4. Verify Adjuster Registration
Spree.adjusters.include?(Spree::Adjusters::DelhiveryCodFee) # => true
```

### Via Spree Admin Dashboard:
1. Log in to `http://localhost:5173/admin`.
2. Visit **Settings $\rightarrow$ Integrations**: Confirm **Delhivery** appears in the gallery with a "Configure" link.
3. Visit **Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods**: Confirm **Delhivery Express** and **Delhivery Surface** are listed.
4. Visit **Settings $\rightarrow$ Payments**: Confirm **Cash on Delivery (Delhivery COD)** is listed.

---

## Troubleshooting

### Error: `Faraday::TimeoutError` during rate calculation or fulfillment
- **Cause**: Network latency or carrier API lag exceeding default gateway timeout.
- **Fix**: The integration includes a built-in 25-second lease-safe boundary. Check that your server can access `https://track.delhivery.com` and `https://stage-express.delhivery.com`.

### Error: `Errno::EACCES (Permission denied @ dir_s_mkdir - /rails/storage/...)`
- **Cause**: In Docker environments running as UID `1000:1000`, the persistent storage directory was created by `root`.
- **Fix**: Run `chown -R 1000:1000 /path/to/storage` on the host volume.

### Error: `No delivery rates available at checkout`
- **Cause**: The shipping address destination country/state is not assigned to a Shipping Zone that includes Delhivery delivery methods.
- **Fix**: In **Settings $\rightarrow$ Shipping $\rightarrow$ Zones**, ensure India or your delivery region is mapped to the zones associated with Delhivery delivery methods.
