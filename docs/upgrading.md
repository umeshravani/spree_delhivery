# Upgrading Spree Delhivery

This guide explains how to safely update the **Spree Delhivery** extension and manage dependencies alongside Spree Commerce core upgrades.

---

## 1. Upgrading the Gem

When a new version or commit of `spree_delhivery` is released:

### Using Spree CLI:
```bash
# Update only the spree_delhivery gem without touching other dependencies
pnpm spree bundle update spree_delhivery

# Restart the development stack
pnpm spree restart
```

### Using Standard Bundler:
```bash
bundle update spree_delhivery
bin/rails restart
```

---

## 2. Upgrading Alongside Spree Core (e.g., Spree 6.0.0 $\rightarrow$ 6.0.1)

When upgrading Spree Commerce minor or patch releases:

1. **Review Release Notes**: Check `CHANGELOG.md` for any deprecations or changes to `Spree.adjusters` or `Spree::Integration`.
2. **Conservative Lockfile Updates**: Update Spree and Spree Delhivery together:
   ```bash
   pnpm spree bundle update spree spree_delhivery
   ```
3. **Run RSpec Test Suite**:
   ```bash
   pnpm spree rspec spec/
   ```
4. **Verify COD Surcharge in Staging**:
   - Add an item to cart.
   - Switch between Cash on Delivery and a card/UPI method.
   - Confirm `Spree::Fee(kind: 'cod')` attaches when COD is active and detaches when prepaid is active.

---

## 3. Rollback Procedure

If an upgrade introduces an unexpected issue:

1. Revert `server/Gemfile.lock` to the previous commit:
   ```bash
   git checkout HEAD~1 -- server/Gemfile.lock
   ```
2. Rebuild or restart the container:
   ```bash
   pnpm spree restart
   ```
3. Because Spree Delhivery introduces no custom database migrations, rolling back gem versions requires **no database rollbacks**.
