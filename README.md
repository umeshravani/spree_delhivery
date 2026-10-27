<img width="300" height="auto" alt="delhivery Header" src="https://github.com/user-attachments/assets/c3fb2919-a732-4719-905a-54d202380703" /><br>

# Spree Delhivery (Spree 6 / Next.js Storefront)

This plugin integrates **Delhivery** with Spree Commerce 6 (tested & verified on `6.0.0` with Rails 8.1) for automated shipping rate calculations, multi-vendor marketplace fulfillment, and a dynamic **Cash on Delivery (COD) Surcharge** that works seamlessly with the official Spree 6 Next.js Storefront.

---

## Compatibility

- **Spree Commerce**: `6.0.0`
- **Rails**: `8.1.x`
- **Ruby**: `>= 3.2`
- **Storefront**: Spree 6 Next.js Storefront (API V3)

---

## Features

- **Live Shipping Rates**: Real-time shipping rate calculation (`Delhivery Surface` and `Delhivery Express`) via Delhivery's Kinko API.
- **Exact Decimals & Currency-Aware**: Fully compliant with Spree 6 rc3/rc6 money correctness (`BigDecimal` exact decimals, currency-scoped rates matching cart currency `INR`).
- **Admin Integrations Gallery**: Automatically registers in Spree Admin Settings > Integrations with official Delhivery branding and documentation links (`Spree::ProviderListing`).
- **Encrypted Secrets at Rest**: API token is securely stored in `secret_preferences` with Rails Active Record encryption (`V-3730`).
- **Automated Fulfillment**: AWB assignment, label generation, and dispatch tracking through Delhivery APIs.
- **Multi-Vendor Marketplace Aware**:
  - Dynamically extracts vendor seller details for Spree 6 split orders (`R10...-1`, `R10...-2`).
  - Matches exact registered vendor stock locations in Delhivery for pickup routing and packing slip labels.
- **Dynamic Cash on Delivery (COD) Surcharge**:
  - Configurable surcharge amount (e.g. ₹90.00) in Admin Integrations.
  - Automatically applied as a `Spree::Fee` (`kind: 'cod'`) via Spree 6's native Adjuster pipeline (`Spree::Adjusters::Base`).
  - Surcharge dynamically appears in storefront checkout when COD is selected and disappears when switching to prepaid methods (e.g. Razorpay).
  - Preserved on the order through `Spree::Carts::Complete` into order totals, fees, and customer invoices.

---

## Screenshots
<img width="1369" height="969" alt="Delhivery Integration Spree 6" src="https://github.com/user-attachments/assets/b2d9b730-14ab-4ea9-95b7-55382c3dfe13" />
<img width="728" height="968" alt="Delhivery Configuration Spree 6" src="https://github.com/user-attachments/assets/cf02cb60-0bb5-408e-95be-9d9d244ca9cb" />
<img width="1369" height="845" alt="Delhivery Profiles Spree 6" src="https://github.com/user-attachments/assets/b1b3f8b4-29b6-4cb0-8c1d-3f4e293c617e" />
<img width="1202" height="1004" alt="Delhivery Checkout Page Spree 6" src="https://github.com/user-attachments/assets/315b41c9-962e-4bc6-a2fc-e230c7e55d1a" />

## Installation & Setup

### 1. Add Plugin to Gemfile

#### From GitHub Pre-Release Branch (Recommended for Production / Deployment):
In `server/Gemfile`:
```ruby
gem 'spree_delhivery', github: 'umeshravani/spree_delhivery', branch: 'pre-release'
```

#### Or for Local Monorepo Development:
```ruby
gem 'spree_delhivery', path: 'plugins/delhivery'
```

Run bundle install:
```bash
bundle install
```

### 2. Auto-Seed Delhivery Profile, Delivery Methods & COD Payment Method

You can automatically create the **Delhivery Delivery Profile**, both delivery methods (**Delhivery Express** & **Delhivery Surface**), and the **Delhivery COD Payment Method** by running the install rake task:

```bash
bin/rails spree_delhivery:install
```
*(Or `bin/rails spree_delhivery:seeds`)*

This creates:
- **Delivery Profile**: `Delhivery` (`Spree::DeliveryProfiles::Shipping`)
- **Delivery Methods**:
  1. `Delhivery Express` (Rate Provider & Fulfillment Provider: `Delhivery`)
  2. `Delhivery Surface` (Rate Provider & Fulfillment Provider: `Delhivery`)
- **Payment Method**: `Cash on Delivery (Delhivery COD)` (`Spree::PaymentMethod::DelhiveryCod`)

---

### 3. Configure Delhivery in Spree Admin

1. Log in to the Spree Admin Dashboard (`/admin` or `http://localhost:5173`).
2. Go to **Settings > Integrations > Delhivery**.
3. Fill in your Delhivery credentials:
   - **API Token**: Your Delhivery production or sandbox API token (stored encrypted).
   - **Client Name**: Your Delhivery registered client name.
   - **Pickup Location**: The registered pickup location/warehouse name in your Delhivery dashboard.
   - **COD Surcharge**: The extra fee to charge customers who choose Cash on Delivery (e.g., `90` for ₹90.00). Leave `0` for free COD.
4. Save the integration.

---

## Storefront (Next.js) Implementation Guide

To integrate the Delhivery plugin with a fresh Spree 6 Next.js Storefront (`apps/storefront`), make the following updates across 3 key files:

### 1. Display Surcharge in Checkout Summary

By default, the storefront checkout summary renders tax and shipping, but not fees. Add the `COD Surcharge` row.

**File:** `apps/storefront/src/components/checkout/Summary.tsx`

Locate the `tax` total row in the totals section and insert the `fee_total` block right after it:

```tsx
{parseFloat(cart.tax_total ?? "0") > 0 && (
  <div className="flex justify-between text-sm">
    <span className="text-gray-700">{tc("tax")}</span>
    <span className="text-gray-900">{cart.display_tax_total}</span>
  </div>
)}

{/* Add COD Surcharge row */}
{parseFloat(cart.fee_total ?? "0") > 0 && (
  <div className="flex justify-between text-sm">
    <span className="text-gray-700">COD Surcharge</span>
    <span className="text-gray-900">{cart.display_fee_total}</span>
  </div>
)}
```

---

### 2. Display Surcharge on Order Confirmation & Order Detail Pages

Ensure the customer and admin see the COD fee on the order thank-you page and in customer account history.

**File:** `apps/storefront/src/components/order/OrderTotals.tsx`

Locate the `tax` total row and add the `fee_total` block:

```tsx
{Number.parseFloat(order.tax_total ?? "0") > 0 && (
  <div className="flex justify-between text-sm">
    <span className="text-gray-500">{t("tax")}</span>
    <span className="text-gray-900">{order.display_tax_total}</span>
  </div>
)}

{/* Add COD Surcharge row */}
{Number.parseFloat(order.fee_total ?? "0") > 0 && (
  <div className="flex justify-between text-sm">
    <span className="text-gray-500">COD Surcharge</span>
    <span className="text-gray-900">{order.display_fee_total}</span>
  </div>
)}
```

---

### 3. Server Actions Return Updated Cart

**File:** `apps/storefront/src/lib/data/payment.ts`

Ensure `createDirectPayment`, `createCheckoutPaymentSession`, and `updateCheckoutPaymentSession` fetch and return the freshly calculated `cart`:

```typescript
export async function createCheckoutPaymentSession(
  cartId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const session = await getClientForSurface(
      surface,
    ).carts.paymentSessions.create(
      id,
      {
        payment_method_id: paymentMethodId,
        ...(externalData && { external_data: externalData }),
      },
      options,
    );
    updateTag(checkoutTag(surface));
    const cart = await getCart(id, surface);
    return { session, cart };
  }, "Failed to create payment session");
}

export async function createDirectPayment(
  cartId: string,
  paymentMethodId: string,
) {
  return actionResult(async () => {
    const surface = await resolveSurfaceForCart(cartId);
    const options = await getCartOptions(surface);
    const id = await requireCartId(surface);
    const payment = await getClientForSurface(surface).carts.payments.create(
      id,
      { payment_method_id: paymentMethodId },
      options,
    );
    updateTag(checkoutTag(surface));
    const cart = await getCart(id, surface);
    return { payment, cart };
  }, "Failed to create payment");
}
```

---

### 4. Instantaneous Payment Method Toggle in PaymentSection

**File:** `apps/storefront/src/components/checkout/PaymentSection.tsx`

Add `onCartChange?: (cart: Cart) => void` to `PaymentSectionProps`, and invoke `onCartChange(result.cart)` whenever direct payments or payment sessions are created or updated.

```tsx
interface PaymentSectionProps {
  // ...
  onCartChange?: (cart: Cart) => void;
}

// In handleMethodSelect (switching to COD):
createDirectPayment(cart.id, newMethod.id)
  .then((result) => {
    if (result.success && result.cart) {
      onCartChange?.(result.cart);
    }
  })
  .finally(() => {
    setLoading(false);
    router.refresh();
  });

// In createSession (switching to Razorpay / Stripe):
if (result.success && result.session) {
  if (result.cart) {
    onCartChange?.(result.cart);
  }
  router.refresh();
  // ...
}
```

---

### 5. Pass `onCartChange` from CheckoutPageContent

**File:** `apps/storefront/src/app/[country]/[locale]/(checkout)/checkout/[id]/CheckoutPageContent.tsx`

Pass `onCartChange={setCart}` to `<PaymentSection />`:

```tsx
<PaymentSection
  ref={paymentRef}
  cart={cart}
  countries={countries}
  isAuthenticated={isAuthenticated}
  fetchStates={fetchStates}
  onUpdateBillingAddress={handleUpdateBillingAddress}
  onPaymentComplete={handlePaymentComplete}
  onCartChange={setCart}
  processing={processing}
  setProcessing={setProcessing}
  onSessionMethodChange={setIsSessionPayment}
  errors={sectionErrors.payment}
/>
```

---

## How It Works Under the Hood

1. **Spree 6 Cart Architecture**:
   In Spree 6 API V3, checkout is driven by `Spree::Cart`. The plugin registers `Spree::Adjusters::DelhiveryCodFee < Spree::Adjusters::Base` into `Spree.adjusters`.
2. **Dynamic Adjuster Lifecycle**:
   Every time totals recalculate (`cart.recalculate_totals!`), `Spree::Carts::RecalculateTotals` runs all registered adjusters. If a valid `Spree::PaymentMethod::DelhiveryCod` payment is on the cart and no active session method is chosen, the adjuster creates or updates a `Spree::Fee(label: 'COD Surcharge', kind: 'cod', amount: surcharge)`. If the customer switches to prepaid, the adjuster destroys the fee automatically.
3. **Instantaneous Storefront State Sync**:
   Direct payment creation and payment session creation return the newly recalculated `cart` in the server action response, immediately calling `setCart` in `CheckoutPageContent` on the client. Totals, discounts, delivery rates, and COD surcharges reflect instantly without needing address switching or page reload.
3. **API Controller Synchronization**:
   - `PaymentsControllerDecorator`: When `POST /api/v3/store/carts/:id/payments` creates a COD payment, it cancels pending sessions, recalculates `@cart.recalculate_totals!`, and syncs `@payment.amount` to the new total with the surcharge.
   - `PaymentSessionsControllerDecorator`: When `POST /api/v3/store/carts/:id/payment_sessions` initiates a prepaid gateway session, it invalidates any COD checkout payment and recalculates `@cart.recalculate_totals!` to immediately strip the COD surcharge.
4. **Order Placement (`Spree::Carts::Complete`)**:
   During order completion, `copy_typed_lines!` copies the `Spree::Fee` from `cart` to `order`, guaranteeing that totals and fees match exactly across both the customer invoice and Admin order management.

 ## Order Status & Tracking Page
 Check out [Implementation of Order Tracking in Spree 6](/Implementation-Order-Tracking-Docs.md)
 
 ### Order Live Status Breakdown
 <img width="729" height="876" alt="Order Status Delhivery" src="https://github.com/user-attachments/assets/ecd72316-705a-41b5-bbca-f59bc5d01764" />


 ## 🤝 Contributing
 
   Bug reports and pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration.
