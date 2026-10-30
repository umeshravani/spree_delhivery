# Configuring Spree Delhivery

This guide details all configuration options for **Spree Delhivery**, including Spree Admin settings, environment variables, multi-vendor routing, and concurrency safeguards.

---

## 1. Spree Admin Configuration (Recommended)

Spree Delhivery registers directly into Spree 6's native Integrations system (`Spree::Integration`).

### Accessing Configuration
1. Log in to the Spree Admin Dashboard (`/admin` or `http://localhost:5173`).
2. Navigate to **Settings $\rightarrow$ Integrations**.
3. Click on the **Delhivery** tile.

### Available Settings

| Setting | Type | Description | Default |
|:---|:---|:---|:---:|
| **API Token** | Encrypted String | Your Delhivery API authentication token. Stored encrypted at rest via Active Record Encryption (`V-3730`). | `nil` |
| **Client Name** | String | Registered client identification name provided by your Delhivery account manager. | `DelhiveryClient` |
| **Pickup Location** | String | The exact name of your primary pickup warehouse registered in Delhivery Unified Portal. | `nil` |
| **COD Surcharge** | Decimal | Amount to charge customers choosing Cash on Delivery (e.g., `90.00` for ₹90.00). Set to `0` for free COD. | `0.0` |
| **Test Mode** | Boolean | Toggle between Delhivery staging sandbox and live production endpoints. | `false` |

Click **Save Changes** to persist your configuration.

---

## 2. Environment Variables

For Twelve-Factor apps, CI/CD pipelines, or container deployments (such as Docker Compose, Coolify, or Kubernetes), settings can be provided via environment variables.

> [!IMPORTANT]
> Ensure you use the exact variable names below. Notice that **`DELHIVERY_API_TOKEN`** is used (not `DELHIVERY_API_KEY`) and **`DELHIVERY_PICKUP_LOCATION_NAME`** is used (not `DELHIVERY_WAREHOUSE_NAME`).

```env
# Delhivery API Authentication Token
DELHIVERY_API_TOKEN=your_production_token_here

# Registered Pickup Warehouse / Hub Name
DELHIVERY_PICKUP_LOCATION_NAME=Main_Warehouse_Delhi

# Registered Client Name
DELHIVERY_CLIENT_NAME=Acme_Retail_Pvt_Ltd

# Staging / Test Sandbox Flag (true/false)
DELHIVERY_TEST_MODE=false

# Cash on Delivery Surcharge (in store currency, e.g. INR)
DELHIVERY_COD_SURCHARGE=90.00
```

When an environment variable is present, it acts as a reliable fallback if database preferences are unconfigured.

---

## 3. Shipping Zones & Delivery Methods Setup

For Delhivery shipping rates to appear in checkout, the delivery methods must be mapped to active Shipping Zones:

1. Open **Settings $\rightarrow$ Shipping $\rightarrow$ Zones**.
2. Create or open your domestic zone (e.g., **India Domestic**), containing:
   - Country: `India`
   - All States/UTs.
3. Open **Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods**.
4. Configure both methods:
   - **Delhivery Express**:
     - *Rate Provider*: `Delhivery`
     - *Fulfillment Provider*: `Delhivery`
     - *Zones*: Check `India Domestic`
     - *Active*: Yes
     - *Storefront Visible*: Yes
   - **Delhivery Surface**:
     - *Rate Provider*: `Delhivery`
     - *Fulfillment Provider*: `Delhivery`
     - *Zones*: Check `India Domestic`
     - *Active*: Yes
     - *Storefront Visible*: Yes

---

## 4. Multi-Vendor Marketplace Warehouse Routing

If running a multi-vendor marketplace using Spree 6 split orders (`R10...-1`, `R10...-2`):

1. The plugin inspects the seller associated with each line item order group.
2. It dynamically matches the vendor's stock location address against registered Delhivery pickup facilities.
3. Packing slip manifests and AWB generation will automatically dispatch the courier pickup to the appropriate vendor facility rather than a single central warehouse.

---

## 5. Duplicate Booking Protection & Concurrency Safety

Carrier booking requests are sensitive to network timeouts and double-clicks. Spree Delhivery implements robust concurrency protection:

- **Local Coordination Lease**: A transactional lock prevents simultaneous threads from initiating bookings on the same shipment.
- **Faraday HTTP Timeout (25 seconds)**: The HTTP client enforces a strict 25-second socket timeout, guaranteed to return before the local coordination lock expires.
- **Ambiguous Outcome Recovery**: If a booking request times out or experiences an unexpected process crash, the shipment enters an ambiguous holding state. Automatic rebooking is blocked until carrier reconciliation confirms whether an AWB was assigned in Delhivery's systems, preventing duplicate carrier charges.

---

## 6. Endpoints & Sandbox Testing

| Environment | Mode | Tracking & Booking Host | Rates (Kinko) Host |
|:---|:---:|:---|:---|
| **Staging / Sandbox** | `DELHIVERY_TEST_MODE=true` | `https://stage-express.delhivery.com` | `https://stage-express.delhivery.com` |
| **Production** | `DELHIVERY_TEST_MODE=false` | `https://express.delhivery.com` / `https://track.delhivery.com` | `https://express.delhivery.com` |

To test shipping rates without live credentials, the staging sandbox responds to standard pincodes (e.g., Origin: `110001`, Destination: `400001`, Weight: `500g`).
