# Production Order Tracking & Delhivery Live API Integration Guide

This guide provides everything needed to implement a production-grade **Order Tracking & Shipment Details** experience in a Spree 6.0 Next.js storefront with live **Delhivery Tracking API** integration.

### Order Tracking Page
<img width="507" height="610" alt="Order Tracking Page" src="https://github.com/user-attachments/assets/4f02298f-3ce6-414b-b7b7-85f732e62df5" />

### Order Live Status Breakdown
<img width="729" height="876" alt="Order Status Delhivery" src="https://github.com/user-attachments/assets/ecd72316-705a-41b5-bbca-f59bc5d01764" />

---
## 1. Fresh Storefront Setup Checklist

If you are starting from a fresh, untouched Spree storefront, here is the exact list of files to add and modify:

### Summary of Changes (9 Files Total)

| Type | Path | Purpose |
| :--- | :--- | :--- |
| **NEW** | `src/lib/data/tracking.ts` | Delhivery Live Tracking API client & waybill extractor |
| **NEW** | `src/components/order/TrackingTimeline.tsx` | 2-column non-overlapping milestone timeline & live scan logs |
| **NEW** | `src/components/order/OrderNotFoundView.tsx` | Production-grade 404 state with search retry form |
| **NEW** | `src/components/order/OrderLookupView.tsx` | Minimal Shopify-style tracking search page |
| **NEW** | `src/app/[country]/[locale]/(storefront)/order/page.tsx` | `/order` search page route handler |
| **MODIFY** | `src/app/[country]/[locale]/(storefront)/order/[number]/page.tsx` | SSR order & live Delhivery tracking data fetching |
| **MODIFY** | `src/components/order/OrderSummaryCard.tsx` | Strict 1:1 real Spree order & line item data mapping |
| **MODIFY** | `src/components/order/CustomerDetailsCard.tsx` | Structured 3-column customer, shipping & payment info |
| **MODIFY** | `src/components/order/OrderHeader.tsx` | Order header with working Buy Again cart integration |
| **BACKEND** | `server/app/controllers/spree/api/v3/store/orders_controller_decorator.rb` | Case-insensitive & Delhivery AWB order lookup |

---

## 2. Environment Configuration

Add the following credentials to `apps/storefront/.env.local`:

```env
SPREE_API_URL=YOURSPREEAPIURL
SPREE_PUBLISHABLE_KEY=YOURSPREEPUBLISHABLEKEY
DELHIVERY_API_TOKEN=YOURAPITOKEN
```

---

## 3. Backend Setup: Case-Insensitive, AWB, Email & Phone Lookup

Create this Rails decorator to allow Store API lookups by Order Number (`R1026-2`, `r1026-2`), Delhivery AWB (`32966010002730`), Customer Email, and Phone Number (with or without country code):

**File:** `server/app/controllers/spree/api/v3/store/orders_controller_decorator.rb`

```ruby
# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module OrdersControllerDecorator
          def find_order!
            raw_id = CGI.unescape(CGI.unescape(params[:id].to_s.strip)).sub(/^#/, '').strip.gsub('%40', '@')
            cart_pk = Spree::Cart.decode_own_prefixed_id(raw_id) rescue nil

            @order = if cart_pk
                       scope.find_by!(cart_id: cart_pk)
                     elsif raw_id.start_with?('or_')
                       scope.find_by_prefix_id!(raw_id)
                     else
                       # 1. Look up by case-insensitive order number
                       found = scope.where('upper(spree_orders.number) = ?', raw_id.upcase).first
                       # 2. Look up by delivery tracking number / waybill
                       found ||= scope.joins(fulfillments: :deliveries).where(
                         'spree_deliveries.tracking_number ILIKE ? OR spree_deliveries.tracking_url ILIKE ?',
                         "%#{raw_id}%", "%#{raw_id}%"
                       ).first
                       # 3. Look up by fulfillment tracking string
                       found ||= scope.joins(:fulfillments).where(
                         'spree_fulfillments.tracking ILIKE ?', "%#{raw_id}%"
                       ).first
                       # 4. Look up by customer email
                       if raw_id.include?('@')
                         found ||= scope.where('lower(spree_orders.email) = ?', raw_id.downcase).order(completed_at: :desc, id: :desc).first
                         found ||= scope.where('spree_orders.email ILIKE ?', "%#{raw_id}%").order(completed_at: :desc, id: :desc).first
                       end
                       # 5. Look up by phone number (matches national/international formats regardless of country code)
                       digits = raw_id.gsub(/\D/, '')
                       if digits.length >= 7
                         last10 = digits.length >= 10 ? digits[-10..] : digits
                         found ||= scope.joins('LEFT JOIN spree_addresses ON spree_addresses.id = spree_orders.ship_address_id OR spree_addresses.id = spree_orders.bill_address_id')
                                        .where('REGEXP_REPLACE(spree_addresses.phone, \'[^0-9]\', \'\', \'g\') LIKE ?', "%#{last10}%")
                                        .order(completed_at: :desc, id: :desc).first
                       end

                       found || scope.find_by!(number: raw_id)
                     end
          end

          def scope
            base_scope = current_store.orders.complete
            # If user or token provided, enforce policy scoping. Otherwise allow public tracking lookup on complete orders.
            if order_token.present? || current_user.present?
              storefront_access_policy.scope(base_scope, token: order_token)
            else
              base_scope
            end.includes(:market, :fulfillments)
          end
        end
      end
    end
  end
end

Spree::Api::V3::Store::OrdersController.prepend(Spree::Api::V3::Store::OrdersControllerDecorator)
```

---

## 4. Frontend Implementation

### Step 1: Live Delhivery Tracking Client (`src/lib/data/tracking.ts`)

```typescript
export interface DelhiveryScanEvent {
  scan: string;
  instructions: string;
  dateTime: string;
  location: string;
  statusCode?: string;
}

export interface DelhiveryTrackingInfo {
  waybill: string;
  status: string;
  statusType?: string;
  statusCode?: string;
  statusDateTime: string | null;
  statusLocation: string | null;
  statusInstructions: string | null;
  origin: string | null;
  destination: string | null;
  expectedDeliveryDate: string | null;
  pickupDateTime: string | null;
  senderName: string | null;
  scans: DelhiveryScanEvent[];
}

export function extractWaybill(trackingOrUrl?: string | null): string | null {
  if (!trackingOrUrl) return null;
  const str = trackingOrUrl.trim();
  const match = str.match(/(?:package\/|waybill=|\b)(\d{10,16})\b/);
  return match ? match[1] : str.replace(/\D/g, "").slice(0, 16) || null;
}

export async function getDelhiveryTracking(
  waybillOrUrl?: string | null,
): Promise<DelhiveryTrackingInfo | null> {
  const waybill = extractWaybill(waybillOrUrl);
  if (!waybill) return null;

  const token =
    process.env.DELHIVERY_API_TOKEN ||
    "56e65b9b621efb43466df2cb99da9481ba3b80bb";

  try {
    const url = `https://track.delhivery.com/api/v1/packages/json/?waybill=${encodeURIComponent(waybill)}`;
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Token ${token}`,
        Accept: "application/json",
      },
      next: { revalidate: 60 },
    });

    if (!response.ok) return null;

    const data = await response.json();
    const shipmentData = data?.ShipmentData?.[0]?.Shipment;
    if (!shipmentData) return null;

    const scans: DelhiveryScanEvent[] = Array.isArray(shipmentData.Scans)
      ? shipmentData.Scans.map((s: any) => {
          const detail = s.ScanDetail || s;
          return {
            scan: detail.Scan || detail.scan || "Status Update",
            instructions: detail.Instructions || detail.instructions || "",
            dateTime: detail.ScanDateTime || detail.StatusDateTime || "",
            location:
              detail.ScannedLocation ||
              detail.Location ||
              detail.StatusLocation ||
              "",
            statusCode: detail.StatusCode || detail.statusCode || "",
          };
        })
      : [];

    return {
      waybill: shipmentData.AWB || waybill,
      status: shipmentData.Status?.Status || "In Transit",
      statusType: shipmentData.Status?.StatusType || "",
      statusCode: shipmentData.Status?.StatusCode || "",
      statusDateTime: shipmentData.Status?.StatusDateTime || null,
      statusLocation: shipmentData.Status?.StatusLocation || null,
      statusInstructions: shipmentData.Status?.Instructions || null,
      origin: shipmentData.Origin || null,
      destination: shipmentData.Destination || null,
      expectedDeliveryDate: shipmentData.ExpectedDeliveryDate || null,
      pickupDateTime: shipmentData.PickUpDateTime || null,
      senderName: shipmentData.SenderName || null,
      scans,
    };
  } catch (error) {
    console.error(`[Delhivery Tracking] Error:`, error);
    return null;
  }
}
```

### Step 2: Tracking Page Route (`src/app/[country]/[locale]/(storefront)/order/[number]/page.tsx`)

```typescript
import type { Metadata } from "next";
import { connection } from "next/server";
import { OrderNotFoundView } from "@/components/order/OrderNotFoundView";
import { OrderTrackingView } from "@/components/order/OrderTrackingView";
import { getOrder } from "@/lib/data/orders";
import { extractWaybill, getDelhiveryTracking } from "@/lib/data/tracking";

interface OrderTrackingPageProps {
  params: Promise<{
    country: string;
    locale: string;
    number: string;
  }>;
}

export async function generateMetadata({
  params,
}: OrderTrackingPageProps): Promise<Metadata> {
  const { number } = await params;
  return {
    title: `Order #${number} - Tracking & Details`,
    description: `Track shipment and view order summary for #${number}`,
  };
}

export default async function OrderTrackingPage({
  params,
}: OrderTrackingPageProps) {
  await connection();
  const { country, locale, number } = await params;
  const basePath = `/${country}/${locale}`;
  const decodedQuery = decodeURIComponent(number || "").trim();

  const order = await getOrder(decodedQuery);
  if (!order) {
    return <OrderNotFoundView number={decodedQuery} basePath={basePath} />;
  }

  const fulfillment = order.fulfillments?.[0];
  const rawTracking =
    fulfillment?.tracking ||
    (fulfillment as any)?.tracking_number ||
    (fulfillment as any)?.deliveries?.[0]?.tracking_number ||
    (fulfillment as any)?.deliveries?.[0]?.tracking_url ||
    fulfillment?.tracking_url ||
    null;

  const waybill = extractWaybill(rawTracking);
  let liveTracking = null;
  if (waybill) {
    liveTracking = await getDelhiveryTracking(waybill);
  }

  return (
    <OrderTrackingView
      order={order}
      liveTracking={liveTracking}
      basePath={basePath}
      locale={locale}
    />
  );
}
```

### Step 3: Search Route (`src/app/[country]/[locale]/(storefront)/order/page.tsx`)

```typescript
import type { Metadata } from "next";
import { OrderLookupView } from "@/components/order/OrderLookupView";

interface OrderSearchPageProps {
  params: Promise<{
    country: string;
    locale: string;
  }>;
}

export const metadata: Metadata = {
  title: "Track Your Order - Live Carrier Tracking",
  description: "Track your shipment, view carrier milestone updates, and check delivery status.",
};

export default async function OrderSearchPage({
  params,
}: OrderSearchPageProps) {
  const { country, locale } = await params;
  const basePath = `/${country}/${locale}`;

  return <OrderLookupView basePath={basePath} />;
}
```

### Step 4: Search Component (`src/components/order/OrderLookupView.tsx`)

```typescript
"use client";

import { ArrowRight, Headphones, Loader2, Mail, Search, ShieldCheck, Truck } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

interface OrderLookupViewProps {
  basePath: string;
}

export function OrderLookupView({ basePath }: OrderLookupViewProps) {
  const router = useRouter();
  const [mode, setMode] = useState<"order" | "contact">("order");
  const [orderQuery, setOrderQuery] = useState("");
  const [contactQuery, setContactQuery] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const clean = (mode === "order" ? orderQuery : contactQuery).trim();
    if (!clean) {
      toast.error(
        mode === "order"
          ? "Please enter an order number or tracking number"
          : "Please enter your email address or phone number"
      );
      return;
    }

    setIsLoading(true);

    try {
      router.push(`${basePath}/order/${encodeURIComponent(clean)}`);
    } catch (err) {
      console.error("Navigation error:", err);
      setIsLoading(false);
      toast.error("Unable to search for order. Please try again.");
    } finally {
      setTimeout(() => setIsLoading(false), 2500);
    }
  };

  return (
    <div className="min-h-[75vh] bg-gray-50/50 py-16 px-4 sm:px-6 lg:px-8 flex flex-col justify-center">
      <div className="max-w-md w-full mx-auto space-y-8">
        <div className="text-center space-y-2">
          <div className="w-12 h-12 rounded-2xl bg-primary/10 text-primary flex items-center justify-center mx-auto mb-4">
            <Truck className="w-6 h-6" />
          </div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-gray-900">
            Track Your Shipment
          </h1>
          <p className="text-sm text-gray-500 max-w-xs mx-auto">
            Check live delivery status and carrier milestones for your order.
          </p>
        </div>

        <div className="bg-white rounded-2xl shadow-xs border border-gray-200/80 p-6 sm:p-8 space-y-6">
          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "order" ? (
              <div className="space-y-2">
                <label
                  htmlFor="order-search-input"
                  className="text-xs font-semibold text-gray-700 block uppercase tracking-wider"
                >
                  Order or Tracking Number
                </label>
                <div className="relative">
                  <Search className="w-4 h-4 text-gray-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <Input
                    id="order-search-input"
                    type="text"
                    placeholder="Search by Order no or AWB"
                    value={orderQuery}
                    onChange={(e) => setOrderQuery(e.target.value)}
                    className="pl-10 h-11 rounded-xl text-sm border-gray-200 focus:border-gray-900 focus:ring-1 focus:ring-gray-900 font-mono"
                    autoComplete="off"
                    required
                  />
                </div>
                <div className="pt-0.5">
                  <button
                    type="button"
                    onClick={() => setMode("contact")}
                    className="text-xs text-gray-900 font-medium hover:underline transition-colors"
                  >
                    Search by Email or Phone number instead
                  </button>
                </div>
              </div>
            ) : (
              <div className="space-y-2">
                <label
                  htmlFor="contact-search-input"
                  className="text-xs font-semibold text-gray-700 block uppercase tracking-wider"
                >
                  Email or Phone Number
                </label>
                <div className="relative">
                  <div className="absolute left-3.5 top-1/2 -translate-y-1/2 flex items-center gap-1 text-gray-400">
                    <Mail className="w-3.5 h-3.5" />
                  </div>
                  <Input
                    id="contact-search-input"
                    type="text"
                    placeholder="Search by Email or Phone number"
                    value={contactQuery}
                    onChange={(e) => setContactQuery(e.target.value)}
                    className="pl-10 h-11 rounded-xl text-sm border-gray-200 focus:border-gray-900 focus:ring-1 focus:ring-gray-900"
                    autoComplete="off"
                    required
                  />
                </div>
                <div className="pt-0.5">
                  <button
                    type="button"
                    onClick={() => setMode("order")}
                    className="text-xs text-gray-900 font-medium hover:underline transition-colors"
                  >
                    Search by Order no or AWB instead
                  </button>
                </div>
              </div>
            )}

            <Button
              type="submit"
              disabled={
                isLoading ||
                (mode === "order" ? !orderQuery.trim() : !contactQuery.trim())
              }
              className="w-full h-11 rounded-xl bg-gray-900 hover:bg-gray-800 text-white font-semibold text-sm gap-2 shadow-xs transition-all"
            >
              {isLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Looking up shipment...</span>
                </>
              ) : (
                <>
                  <span>Track Shipment</span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </Button>
          </form>

          <div className="pt-4 border-t border-gray-100 flex items-center gap-2 text-xs text-gray-500">
            <ShieldCheck className="w-4 h-4 text-emerald-600 flex-shrink-0" />
            <span>Secure live tracking via official carrier API</span>
          </div>
        </div>

        <div className="text-center text-xs text-gray-500 flex items-center justify-center gap-1.5">
          <Headphones className="w-3.5 h-3.5 text-gray-400" />
          <span>
            Need help finding your order?{" "}
            <a
              href="mailto:support@mystore.com"
              className="text-gray-900 font-semibold underline hover:text-gray-700"
            >
              Contact Support
            </a>
          </span>
        </div>
      </div>
    </div>
  );
}
```

---

## 5. Troubleshooting & Gotchas

1. **Store Timezone:**
   Ensure `Spree::Store.default.preferred_timezone` is set to a valid ActiveSupport zone like `"Asia/Kolkata"` rather than `"Asia/Calcutta"` to avoid cart errors on reorders.

2. **Retail Price Availability:**
   Ensure variants have base retail prices with `price_list_id: nil` in addition to wholesale price lists so items can be re-ordered into active carts.

3. **Missing Message Console Warnings:**
   Ensure all order, shipment, and payment statuses (`paid`, `partiallyPaid`, `unfulfilled`, `placed`, `pending`) are registered in `messages/en.json` under `"orders"`.

