# Spree Delhivery Integration

<img width="300" height="auto" alt="delhivery Header" src="https://github.com/user-attachments/assets/c3fb2919-a732-4719-905a-54d202380703" /><br>

This extension provides a comprehensive integration between **Spree Commerce** and **Delhivery Logistics**. It streamlines your shipping workflow by allowing you to generate waybills, schedule pickups, print labels, and track shipments directly from the Spree Admin panel. It also enhances the customer experience with a storefront delivery availability widget.

## 🚀 Key Features

### 📦 Admin Logistics & Fulfillment
* **Live Shipping Rates:** Automatically calculates shipping costs based on product weight (volumetric vs actual) and distance.
* **One-Click Manifesting:** Generate Delhivery Waybills and tracking numbers directly from the Shipment card.
* **Label Printing:** Download and print official PDF shipping labels (AWB).
* **Pickup Scheduling:** Schedule carrier pickups for specific dates and times directly from the Admin UI.
* **Tracking Sync:** Real-time status updates (e.g., *In Transit, Out for Delivery, Delivered, RTO*) displayed with color-coded badges.
* **Cancellation:** Void/Cancel waybills before pickup directly from Spree.

### 📍 Warehouse Management (Geolocation)
* **Interactive Map:** Upgraded Stock Location form with a **Leaflet.js** map.
* **Pinpoint Accuracy:** Search for cities or drag the pin to set precise Latitude/Longitude for accurate pickup calculations.
* **Auto-Fill:** Automatically captures coordinates to ensure accurate logistics routing.

### 🛍️ Storefront Experience (PDP Widget)
* **Delivery Checker:** Users can enter their Pincode to check serviceability.
* **Smart Location Detection:** improved logic to detect and display **"City, District, State"** (e.g., *Bardoli, Surat, Gujarat*) instead of just the post office name.
* **Estimated Delivery Date (EDD):** Shows dynamic delivery dates based on Delhivery TAT API.
* **Countdown Timer:** "Order within 2 hrs 30 mins for delivery by Tuesday" logic.
* **Customizable UI:** Admin controls for widget colors, headings, and placeholder text.

---

## 🛠 Installation

1. Add this line to your application's `Gemfile`:

```ruby
gem 'spree_delhivery', github: 'umeshravani/spree_delhivery'
```
2. Install the Gem:

```ruby
bundle install
```
3. Run the installation generator:

   • This installs migrations.<br>
   • Runs migrations (optional).<br>
   • Seeds Shipping Methods: Automatically creates "Delhivery Surface" and "Delhivery Express" shipping methods with correct preferences.

```ruby
bundle exec rails g spree_delhivery:install
```
<br>

 ## ⚙️ Configuration
 
 ### 1. General Settings
  
  Go to Admin Panel -> Integrations -> Delhivery.
  
<img width="279" height="332" alt="Integrations Page" src="https://github.com/user-attachments/assets/3da6c1be-92b3-410c-ab00-f0bb27e79099" /><br>
  

  • API Token: Enter your Delhivery API Token (masked for security).

  • Production Mode: Check this box for live shipments. Uncheck for Sandbox/Testing.

  • Pickup Location: Crucial. This must match the exact warehouse name registered in your Delhivery Dashboard.

  • Unit Mapping: Select how your store stores Weight (kg/lbs) and Dimensions (cm/in) so the calculator converts them correctly for the API.<br>

  <img width="500" height="auto" alt="Integration Settings Delhivery" src="https://github.com/user-attachments/assets/d74ff3ca-13c2-4ff4-9465-2f7e483a9955" /><br>


  ### 2. Shipping Methods
  
   If you didn't seed them during install, create a Shipping Method in Admin -> Shipping -> Shipping Methods:

  • Calculator: Select Delhivery Live Rate.

  • Service Mode: Enter Surface or Express.

  • Tracking URL: https://www.delhivery.com/track/package/:tracking <br>

  <img width="800" height="auto" alt="Shipping Methods (Auto Added)" src="https://github.com/user-attachments/assets/017a6fda-3059-4bfc-97aa-29f21674e1b4" /><br>


  ### 3. Widget Configuration
  
  Go to Admin -> Content -> Page Blocks -> Delhivery EDD.

  • Customize the Heading, Button Text, and Colors.

  • Set the Cutoff Time (e.g., 2:00 PM) to control the "Order within..." countdown timer.<br>

  <img width="800" height="auto" alt="Delhivery EDD Widget" src="https://github.com/user-attachments/assets/8802836d-ad0c-4ccb-9bad-629a508322ae" /><br>


 ## 🖥️ Usage Guide
 
  ### Fulfillment Workflow (Admin)
  
  1. Navigate to Orders -> Order # -> Shipments.

  2. You will see the unified Delhivery Toolbar on the shipment card.

  3. Ship: Click "Ship with Delhivery". This generates the AWB.

  4. Print: Click the Printer icon to get the PDF label.

  5. Pickup: Click the Truck icon to open the Schedule Pickup Modal. Select date/time and confirm.

  6. Track: Click the Refresh icon to pull the latest status from Delhivery.<br>

  
  <img width="800" height="auto" alt="Orders Page (Unshipped Order)" src="https://github.com/user-attachments/assets/1c1527b3-4096-4b26-a594-5ebe3f528677" /><br>

  <img width="800" height="560" alt="Shipped Order (Orders Page)" src="https://github.com/user-attachments/assets/9dc19710-e5b9-4e69-a862-ea7d02d1cb13" /><br>


 ### Storefront Widget
 
  To display the Pincode checker on your product page, add this helper to your products/show view file:

  1. Find your Partial file Example: 
  ```
    'app/views/themes/default/spree/page_sections/_product_details.html.erb'
  ```
Note: If you dont find this file inside your spree's directory, You can [Download](https://github.com/spree/spree/blob/df400d3557c244ec3829f175a27f3990cdeb2452/storefront/app/views/themes/default/spree/page_sections/_product_details.html.erb#L4) this directly from Spree's Github and place it exactly inside your Spree's directory

  2. Place this Rendering Code:
  
   ```ruby
    <% when 'Spree::PageBlocks::Products::DelhiveryEdd' %>
    <%= block.render(self, product: product) %> 
   ```
  3. Exactly below this part:
   ```
    <% when 'Spree::PageBlocks::Products::Description' %>
   ```

 ## 🧩 Technical Details
 
 • Maps: Uses OpenStreetMap + Leaflet.js (No Google Maps API key required).


 • Turbo Support: Fully compatible with Turbo Drive; map re-initializes correctly on page transitions.


 • Styling: Uses Tailwind CSS utility classes matching Spree's default admin theme.


 • Calculations: Handles volumetric weight calculation (L x W x H) / 5000 automatically based on your unit settings.<br>

 <img width="800" height="auto" alt="Stock Locations Page (Delhivery Settings)" src="https://github.com/user-attachments/assets/729f5abf-afe7-430f-87ef-93a52997e0c4" /><br>


 ## 🛒 Checkout Page Auto-Calculation
 
 Eliminate guesswork and undercharging for shipping. This extension integrates directly into the Spree Checkout flow (Delivery Step) to provide accurate costs instantly.

 • Live API Calls: As soon as a customer enters their shipping address, the calculator queries the Delhivery API for real-time rates based on the specific source and destination pincodes.

 • Volumetric Weight Logic: Automatically calculates (Length x Width x Height) / 5000 and compares it against the actual weight. The API requests the rate based on whichever is higher, ensuring you never lose money on bulky, lightweight items.

 • Performance Caching: Rate responses are cached for 15 minutes to ensure fast page loads and prevent hitting API rate limits during high traffic.

 • Handling Fee Support: Easily add a fixed handling/packing fee on top of the live carrier rate via the Shipping Method preferences.<br>
 
 <br><img width="800" height="auto" alt="Checkout Page (Auto Calculate Shipping Costs)" src="https://github.com/user-attachments/assets/aa983ad0-638a-4140-971f-f1f56dead652" />



 ## 🤝 Contributing
 
   Bug reports and pull requests are welcome on GitHub. This project is intended to be a safe, welcoming space for collaboration.
