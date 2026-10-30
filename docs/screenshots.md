# Spree Delhivery Screenshot Documentation & Visual Guide

This document catalogs the required visual documentation for **Spree Delhivery**, provides standard capture guidelines, and details privacy masking procedures for screenshots in public documentation.

---

## 1. Screenshot Inventory & Checklist

Store all screenshot assets in `docs/assets/screenshots/` using standard lowercase kebab-case naming.

| ID | File Name | Screen Description | Location in App | Status |
|:---|:---|:---|:---|:---:|
| `DLH-01` | `01-admin-integrations-gallery.png` | Spree Admin Integrations card showing official Delhivery branding | Admin $\rightarrow$ **Settings $\rightarrow$ Integrations** | Pending capture |
| `DLH-02` | `02-admin-delhivery-configuration.png` | Delhivery Credentials & Settings form (Client name, Pickup location, COD fee) | Admin $\rightarrow$ **Settings $\rightarrow$ Integrations $\rightarrow$ Delhivery** | Pending capture |
| `DLH-03` | `03-admin-delivery-methods-list.png` | Delivery methods table displaying *Delhivery Express* and *Delhivery Surface* | Admin $\rightarrow$ **Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods** | Pending capture |
| `DLH-04` | `04-storefront-checkout-shipping-rates.png` | Storefront delivery step displaying live calculated Delhivery rates | Storefront $\rightarrow$ Checkout Delivery Step | Pending capture |
| `DLH-05` | `05-storefront-checkout-cod-surcharge.png` | Payment step with Cash on Delivery selected and dynamic COD Surcharge fee | Storefront $\rightarrow$ Checkout Payment Step & Summary | Pending capture |
| `DLH-06` | `06-admin-shipment-awb-assignment.png` | Admin order fulfillment card showing generated Delhivery AWB & label | Admin $\rightarrow$ **Orders $\rightarrow$ [Order Number] $\rightarrow$ Shipments** | Pending capture |
| `DLH-07` | `07-storefront-order-tracking-timeline.png` | Customer-facing tracking page with 2-column live milestone timeline | Storefront $\rightarrow$ `/order/[number]` or `/order` lookup | Pending capture |

---

## 2. Capture Guidelines & Specifications

To ensure crisp visual consistency across all documentation, contributors should adhere to the following standards:

### Image Specifications
- **Format**: PNG (`.png`), optimized with `pngquant` or ImageOptim (target file size $\le 450 \text{ KB}$).
- **Pixel Density**: Standard 2x Retina capture.
- **Viewport Dimensions**:
  - **Admin screens**: $1440 \times 900 \text{ px}$ (window size $1280 \times 800 \text{ px}$ with standard browser frame or cropped cleanly).
  - **Storefront desktop checkout**: $1280 \times 800 \text{ px}$.
  - **Storefront mobile views / Tracking**: $390 \times 844 \text{ px}$ (iPhone 14/15 profile).
- **Color Scheme**: Capture in Light Mode using the default Spree brand styling.

### Capture Steps per Screenshot

#### `DLH-01: Admin Integrations Gallery`
1. Navigate to `http://localhost:5173/admin` (or `/admin`).
2. Go to **Settings $\rightarrow$ Integrations**.
3. Locate the **Delhivery** tile displaying the provider logo, active indicator, and "Configure" button.
4. Capture the grid card and surrounding provider tiles.

#### `DLH-02: Delhivery Configuration Form`
1. Click **Configure** on the Delhivery card.
2. Ensure the form fields are populated:
   - **API Token**: Partially masked (e.g. `••••••••••••••••••••••••ba3b80bb`).
   - **Client Name**: Sample client name (e.g., `Acme Wholesale`).
   - **Pickup Location**: Sample registered warehouse (e.g., `Primary_Hub_Delhi`).
   - **COD Surcharge**: `90.00`.
   - **Test Mode**: Checked (`true`) for staging/demo environments.
3. Capture the drawer or settings page including the **Save Changes** button.

#### `DLH-03: Delivery Methods List`
1. Navigate to **Settings $\rightarrow$ Shipping $\rightarrow$ Delivery Methods**.
2. Show both `Delhivery Express` and `Delhivery Surface` configured with:
   - Rate Provider: `Delhivery`
   - Fulfillment Provider: `Delhivery`
   - Zones: All active shipping zones.

#### `DLH-04: Storefront Checkout Shipping Rates`
1. Add an item to the shopping bag on the Next.js storefront.
2. Proceed to Checkout and enter a serviceable Indian PIN code (e.g. `110001` or `400001`).
3. Proceed to the Delivery step to display:
   - `Delhivery Express` with live computed delivery cost.
   - `Delhivery Surface` with estimated delivery timeframe.

#### `DLH-05: Storefront Checkout COD Surcharge`
1. Advance to the Payment step.
2. Select **Cash on Delivery (Delhivery COD)**.
3. In the Order Summary sidebar, ensure the **COD Surcharge** line item (e.g. `₹90.00`) is visible.
4. Click back to a prepaid method (e.g. Razorpay) to show the surcharge disappearing dynamically.

#### `DLH-06: Admin Shipment AWB Assignment`
1. Open an order ready for dispatch in Spree Admin.
2. Click **Ship with Delhivery** or view the generated fulfillment.
3. Capture the assigned Delhivery AWB number (e.g. `32966010002730`), packing slip link, and manifest status.

#### `DLH-07: Storefront Order Tracking Timeline`
1. Visit `http://localhost:3000/en/order/R1026-1` or search the waybill on `/order`.
2. Capture the 2-column milestone view showing:
   - Order Header & Destination details.
   - Carrier milestones: *Manifested*, *In Transit*, *Out for Delivery*, *Delivered*.
   - Exact scan logs with timestamps and hub locations.

---

## 3. Privacy, Security & Masking Checklist

> [!CAUTION]
> Never commit production secrets, live API tokens, or actual customer personally identifiable information (PII) to repository screenshots.

Before committing any screenshot image, verify the following masking checklist:

- [ ] **Delhivery API Token**: Must be hidden or masked showing only the trailing 8 characters (e.g., `••••••••ba3b80bb`).
- [ ] **Customer Names & Contact Details**: Replace real customer data with fictitious names (e.g., `Priya Sharma`, `Rahul Verma`).
- [ ] **Phone Numbers**: Mask to standard test patterns (e.g., `+91 98765 00000` or `+91 99999 XXXXX`).
- [ ] **Email Addresses**: Use standard test domains (e.g., `customer@example.com` or `buyer@demo.store`).
- [ ] **Physical Delivery Addresses**: Redact flat/building numbers; retain only city, state, and pincode (e.g., `Connaught Place, New Delhi, Delhi - 110001`).
- [ ] **Internal Hostnames**: Replace custom internal VPS IP addresses or private domains with `spree.example.com` or `localhost:3000`.
