# Changelog

All notable changes to **Spree Delhivery** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

Changes verified against Spree 6.0.1 on the `spree-6` branch (pending release tagging):

### Added
- Standard Rails installation generator: `rails g spree_delhivery:install` (scaffolds delivery profiles, delivery methods, COD payment method, and default preferences).
- Standalone documentation suite in `docs/`:
  - `installation.md`: Detailed Spree CLI, standard Rails, and Coolify guides.
  - `configuration.md`: Comprehensive guide to Admin preferences, exact environment variables, and shipping zones.
  - `disabling-and-uninstalling.md`: Safe dashboard deactivation vs experimental STI shims.
  - `compatibility.md`: Tested versions matrix and Spree 5 vs 6 architecture guide.
  - `upgrading.md`: Maintenance and safe upgrade procedures.
  - `storefront.md`: Optional Next.js App Router reference guide, COD surcharge summary, and live tracking components.
  - `screenshots.md`: Visual inventory, capture standards, and privacy masking checklist.
- Strict 25-second Faraday HTTP timeout to enforce carrier coordination lease boundary safety.
- Ambiguous outcome tracking: prevents automatic rebooking after network timeouts or crashes until carrier reconciliation confirms booking status.

### Changed
- Refactored `orders_controller_decorator.rb` to handle optional order references in test doubles and missing address scenarios.
- Modernized documentation to clearly distinguish core gem capabilities from optional Next.js storefront components.

---

## [6.0]

### Added
- Native Spree Commerce 6 compatibility (verified on Rails 8.1 and Ruby 3.2+).
- Dynamic Cash on Delivery (COD) Surcharge implemented via Spree 6 Adjusters pipeline (`Spree::Adjusters::DelhiveryCodFee < Spree::Adjusters::Base`).
- Real-time shipping rate calculation for **Delhivery Surface** and **Delhivery Express** via Kinko API charges endpoint.
- Spree Admin Integrations registration via `Spree::ProviderListing` with branded tile in Settings $\rightarrow$ Integrations.
- Encrypted storage for Delhivery API tokens using Rails Active Record encryption (`V-3730`).
- Multi-vendor marketplace support: dynamically matches seller stock locations with registered Delhivery pickup facilities for split orders.
