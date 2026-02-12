# BigQuery Cleanup: Less Tables, Same Data

**Date:** 2026-02-12
**Dataset:** `hulken.ads_data`
**Source:** Analysis of `Hulken Shopify MetaData.txt` + BigQuery audit

---

## The problem

The analyst opens BigQuery and sees **40 names** with raw tables, clean tables, dedup views, lookup tables mixed together. Tables have 97 columns where 30+ are always NULL. The `order_id` format differs between tables. Two orders tables exist with different column names for the same data.

---

## Why we can't move tables

Moving raw tables to another dataset would break Airbyte (3 connections), PII hash scheduled queries (90+ references), clean table refresh, 16 views, and Python scripts. Too risky.

---

## Safe solution: new dataset `ads_analyst`

Create a NEW dataset `ads_analyst` with **15 smart views** that:
- Only expose useful, populated columns (not 97)
- Fix format differences (GID order IDs → numeric)
- Unify duplicate tables (2 orders tables → 1)
- Remove always-NULL columns
- Add cross-platform performance view (Facebook + TikTok combined)
- `ads_data` stays 100% untouched

---

## The 15 views

### shopify_orders (unified, from 2 tables)

Currently `shopify_orders` (bulk, 586K rows, `totalPrice`/`createdAt`) and `shopify_live_orders_clean` (Airbyte, 17K rows, `total_price`/`created_at`) overlap with 8K shared orders and different column names. The unified view combines both, deduplicates on ID (live wins), and exposes only useful columns.

**97 columns → 15 columns:**

| Column | Source | Why keep |
|--------|--------|----------|
| `order_id` | `id` | Numeric ID for joins |
| `order_name` | `name` | Display name (#583346) |
| `created_at` | `created_at` / `createdAt` | Order date |
| `total_price` | `total_price` / `totalPrice` | Revenue |
| `subtotal_price` | `subtotal_price` / `subtotalPrice` | Before tax |
| `total_discounts` | `total_discounts` / `totalDiscounts` | Discounts applied |
| `total_tax` | `total_tax` / `totalTax` | Tax amount |
| `currency` | `currency` / `currencyCode` | USD/CAD/EUR |
| `financial_status` | `financial_status` / `displayFinancialStatus` | paid/refunded/pending |
| `fulfillment_status` | `fulfillment_status` / `displayFulfillmentStatus` | fulfilled/unfulfilled |
| `source_name` | `source_name` | web/pos/api |
| `tags` | `tags` | Amazon, nofraud_skip, etc. |
| `email_hash` | `email_hash` | For customer matching |
| `shipping_country` | from `shipping_address` JSON / `shipping_country` | Country |
| `cancelled_at` | `cancelled_at` | NULL if not cancelled |

**Removed:** `company` (always NULL), `po_number` (always NULL), `device_id` (always NULL), `deleted_at` (always NULL), `payment_terms` (always NULL), 30+ JSON blobs (`line_items`, `customer`, `refunds`, `fulfillments`, `tax_lines`, etc.), 20+ `_set` duplicate columns, all `_airbyte_*` internal columns.

### shopify_customers (from shopify_live_customers_clean)

**28 columns → 10 columns:**

| Column | Why keep |
|--------|----------|
| `customer_id` | Numeric ID |
| `created_at` | Sign-up date |
| `orders_count` | Number of orders (note: may show 0 for old customers) |
| `total_spent` | Lifetime value (note: may show 0 for old customers) |
| `currency` | Customer currency |
| `state` | enabled/disabled |
| `tags` | Customer tags |
| `email_hash` | For matching with orders |
| `last_order_id` | Most recent order |
| `last_order_name` | Most recent order display name |

**Removed:** `first_name` (nullified by PII script), `first_name_hash` (only 90/23K filled), `last_name_hash` (same issue), `addresses_hash`, `default_address_hash`, `phone_hash`, `note` (always empty), `accepts_marketing` (always NULL), `admin_graphql_api_id`, `multipass_identifier`, `marketing_opt_in_level`, `tax_exempt`, `tax_exemptions`, `shop_url`, `sms_marketing_consent`, `email_marketing_consent`, all `_airbyte_*` columns.

### shopify_utm (from shopify_utm, with fixed order_id)

**Fix:** `order_id` currently contains GID format `gid://shopify/Order/6688369770751`. The view extracts the numeric ID so it can be joined directly to `shopify_orders.order_id` without REGEXP.

| Column | Change |
|--------|--------|
| `order_id` | Extracted numeric from GID (`6688369770751` instead of `gid://shopify/Order/6688369770751`) |
| `order_name` | Keep as-is |
| `created_at` | Keep |
| `total_price` | Keep |
| `customer_order_index` | Keep (1 = first order = new customer) |
| `days_to_conversion` | Keep |
| `first_utm_source` | Keep |
| `first_utm_medium` | Keep |
| `first_utm_campaign` | Keep |
| `first_utm_content` | Keep |
| `first_landing_page` | Keep |
| `last_utm_source` | Keep |
| `last_utm_medium` | Keep |
| `last_utm_campaign` | Keep |
| `sales_channel` | Keep |
| `attribution_status` | Keep |

### shopify_products (from ads_data.shopify_products view)

Keep as-is. Already deduplicated.

### shopify_line_items (from ads_data.shopify_line_items)

Keep as-is. Contains order line items (which products in each order).

### facebook_insights (from ads_data.facebook_insights view)

Keep as-is. Already deduplicated. Already has `campaign_name`, `ad_name`, `adset_name`, `account_name` built-in — no need for the separate `facebook_ads`, `facebook_ad_sets`, `facebook_ad_creatives` lookup tables.

### facebook_campaigns_daily (from ads_data.facebook_campaigns_daily view)

Keep as-is. Aggregated by campaign/day.

### facebook_insights_country (from ads_data.facebook_insights_country view)

Keep as-is.

### facebook_insights_age_gender (from ads_data.facebook_insights_age_gender view)

Keep as-is.

### tiktok_reports_daily (from ads_data.tiktok_ads_reports_daily view)

Keep as-is. Already extracts clean columns from JSON.

### tiktok_campaigns_daily (from ads_data.tiktok_campaigns_reports_daily view)

Keep as-is.

### tiktok_campaigns (from ads_data.tiktok_campaigns view)

Keep as-is. Needed for campaign name lookups.

### unified_ads_performance (NEW cross-platform view)

Combines ad spend (Facebook, TikTok) with Shopify revenue (from UTM attribution) into one daily table. This is the **ROAS view** — the analyst sees spend, revenue, and return on ad spend per platform per day.

**How it works:** Ad spend comes from `facebook_insights` and `tiktok_ads_reports_daily`. Revenue comes from `shopify_utm` grouped by `first_utm_source` mapped to each platform. Direct/organic and Amazon revenue (no ad spend) are included as separate channels for the full picture.

| Column | Source |
|--------|--------|
| `date` | `date_start` (Facebook) / `report_date` (TikTok) / `created_at` (Shopify) |
| `platform` | 'facebook', 'tiktok', 'google', 'direct_organic', 'amazon', 'other' |
| `spend` | From ad platform (NULL for organic/amazon) |
| `impressions` | From ad platform (NULL for organic/amazon) |
| `clicks` | From ad platform (NULL for organic/amazon) |
| `shopify_orders` | Count of orders from `shopify_utm` attributed to this platform |
| `shopify_revenue` | Sum of `total_price` from `shopify_utm` attributed to this platform |
| `roas` | Calculated: shopify_revenue / spend (NULL when no spend) |
| `cpc` | Calculated: spend / clicks |
| `cpm` | Calculated: (spend / impressions) * 1000 |

**UTM source mapping:**

| `first_utm_source` in shopify_utm | → `platform` |
|-----------------------------------|-------------|
| `facebook-fb`, `facebook-ig`, `facebook` | facebook |
| `tiktok-TikTok`, `tiktok-unknown` | tiktok |
| `google` | google |
| `Klaviyo`, `omnisend` | email |
| `attribution_status = 'DIRECT_OR_ORGANIC'` | direct_organic |
| `attribution_status = 'AMAZON_NO_TRACKING'` | amazon |
| Everything else | other |

**Real numbers (Feb 2026):**

```
Date        Platform         Spend      Revenue    Orders  ROAS
2026-02-08  facebook        $21,503    $29,722      181    1.38x
2026-02-08  direct_organic       $0    $41,258      250      -
2026-02-08  amazon               $0    $23,699      177      -
2026-02-08  tiktok           $2,740     $1,007        6    0.37x
```

**Why:** The analyst currently queries Facebook spend, TikTok spend, and Shopify revenue in 3 separate queries then manually combines in Excel. This view gives the full daily P&L by channel in one query.

---

## Known bugs found during NULL audit

Full audit: **[NULL_AUDIT_BIGQUERY.md](NULL_AUDIT_BIGQUERY.md)** — every NULL column classified as bug / API design / expected.

### BUG 1: PII script wiped emails BEFORE hashing (CRITICAL) — FIX READY, needs execution

The PII nullify script ran `SET email = NULL` in raw tables. The clean refresh then tries `SHA256(email)` on NULL → produces NULL hash. Raw tables have **no `email_hash` column** — the only hashing happens during clean refresh.

| Table | `email_hash` NULL rate | Expected after fix |
|-------|----------------------|----------|
| `shopify_live_customers_clean` | **59% NULL** (14,026/23,624) | ~2% |
| `shopify_live_orders_clean` | **50.5% NULL** (8,589/17,021) | ~2% |

Also: `first_name_hash`, `last_name_hash`, `phone_hash` are 99.5% NULL in customers_clean.

**Fix applied (code):** `scheduled_refresh_clean_tables.sql` updated to save existing hashes into temp table before `CREATE OR REPLACE`, then restore via `UPDATE ... COALESCE(new_hash, saved_hash)`.

**Remaining action:** Execute the updated SQL in BigQuery Console (or update the scheduled query). Until then, current NULL rates persist. **Workaround:** Use `last_order_id` to join customers ↔ orders.

### BUG 2: TikTok view reads wrong columns (MEDIUM) — FIXED

~~`tiktok_ads_reports_daily` view reads `campaign_id` and `adgroup_id` from top-level columns (100% NULL) instead of `metrics` JSON (100% filled).~~

**Fixed 2026-02-12:** View recreated in BigQuery with `JSON_EXTRACT_SCALAR(metrics, '$.campaign_id')`. Result: **0% → 100% coverage** (30,721 rows). Campaign name joins with `tiktok_campaigns` confirmed working.

### BUG 3: Facebook 2024 missing reach/frequency (LOW) — NOT FIXED

2024 data (42,462 rows) has 100% NULL `reach`, `frequency`, `cpp` because old Airbyte config didn't request these. 2025-2026 data is fine.

**Action needed:** Re-sync 2024 with current Airbyte config (low priority, historical data only).

### 14 always-NULL columns: safe to exclude

These are NULL because the **API never sends them** (not a bug): `company`, `po_number`, `device_id`, `deleted_at`, `payment_terms`, `landing_site_ref`, `accepts_marketing`, `multipass_identifier`, `marketing_opt_in_level`, `message` (transactions), `device_id`/`user_id`/`location_id` (transactions), `advertiser_id` (TikTok).

---

## Pending: 3 Facebook breakdown views

After the Facebook full sync (Job 150) completes with all streams, these additional views can be created:

| View | Source | Status |
|------|--------|--------|
| `facebook_insights_action_type` | Breakdown by conversion type | Waiting for stream data |
| `facebook_insights_dma` | Breakdown by DMA region | Waiting for stream data |
| `facebook_insights_platform_device` | Breakdown by device/platform | Waiting for stream data |

These are **not blocking** the `ads_analyst` dataset creation. They can be added later.

---

## Analyst questions answered

From `Hulken Shopify MetaData.txt`:

| Question | Answer |
|----------|--------|
| "What is the difference with shopify_orders?" | Bulk import (historical, 586K) vs Airbyte live sync (17K). Solved by unified view. |
| "first_name: should not be encrypted" | The PII hash script nullified it. In `ads_analyst`, first_name is removed entirely (not useful without the actual name). |
| "orders_count: why at 0" | Airbyte Shopify connector returns 0 for customers outside the sync window. Known limitation. |
| "total_spent: why is there 0?" | Same reason — Shopify API returns 0 for old/inactive customers. |
| "email: why null?" | PII script nullified emails after hashing. Use `email_hash` for matching. |
| "accepts_marketing: why null?" | 0/23K filled. Shopify API doesn't return this field for the connector used. Removed from view. |
| "note: why null?" | 0/23K filled for customers, 52/42K for orders. Removed from view. |
| "order_id looks like customer_id" (refunds) | Shopify uses same numeric format for all IDs. The refunds table is rarely needed — kept in `ads_data` only. |
| "order_id: gid://shopify/Order/..." (utm) | Fixed in `ads_analyst` view: extracts numeric ID for easy joins. |

---

## Before vs After

```
BEFORE (ads_data)                      AFTER (ads_analyst)
40 names, 97-column tables             15 names, 10-15 columns each

facebook_ad_creatives          |       facebook_insights
facebook_ad_sets               |       facebook_campaigns_daily
facebook_ads                   |       facebook_insights_country
facebook_ads_insights          |       facebook_insights_age_gender
facebook_ads_insights_age...   |
facebook_ads_insights_cou...   |       tiktok_reports_daily
facebook_ads_insights_reg...   |       tiktok_campaigns_daily
facebook_campaigns_daily       |       tiktok_campaigns
facebook_insights              |
facebook_insights_age_gender   |       shopify_orders (unified!)
facebook_insights_country      |       shopify_customers
facebook_insights_region       |       shopify_utm (fixed order_id!)
tiktokads                      |       shopify_products
tiktokads_reports_daily        |       shopify_line_items
tiktokad_groups                |
tiktokad_groups_reports_daily  |
tiktokcampaigns                |       unified_ads_performance (ROAS!)
tiktokcampaigns_reports_daily  |
tiktokadvertisers_reports...   |       + google_Ads (own dataset)
                               |       + analytics_* (own datasets)
shopify_line_items             |
shopify_live_customers         |
shopify_live_customers_clean   |
shopify_live_inventory_items   |
shopify_live_order_refunds     |
shopify_live_orders            |
shopify_live_orders_clean      |
shopify_live_products          |
shopify_live_transactions      |
shopify_orders                 |
shopify_products               |
shopify_refunds                |
shopify_transactions           |
shopify_utm                    |
tiktok_ad_groups               |
tiktok_ad_groups_reports_daily |
tiktok_ads                     |
tiktok_ads_reports_daily       |
tiktok_advertisers_reports...  |
tiktok_campaigns               |
tiktok_campaigns_reports_daily |
```

## What breaks?

**Nothing.** `ads_data` stays 100% untouched.

| Component | Impact |
|-----------|--------|
| Airbyte (3 connections) | No change |
| PII hash scheduled queries | No change |
| Clean table refresh | No change |
| Python scripts | No change |
| Existing views in ads_data | No change |

---

*Suggestions only. No changes made. Confirm before implementing.*
