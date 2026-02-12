# BigQuery NULL Audit: Bug vs API Design vs Expected

**Date:** 2026-02-12
**Audited by:** Automated scan of all `hulken.ads_data` tables
**Purpose:** For each NULL column, determine if data was lost (bug) or never existed (API design)

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| **BUG — data lost** | 7 fields | Fix urgently |
| **API never sends** | 14 fields | Safe to remove from views |
| **Expected by business logic** | 12 fields | Keep, document why NULL |

---

## BUG — Data was available but lost

These NULLs should NOT exist. Data was available from the API but was destroyed or not captured.

### BUG 1: PII script wiped emails BEFORE hashing (CRITICAL)

| Table | Field | NULL rate | What happened |
|-------|-------|-----------|---------------|
| `shopify_live_customers` | `email` | 44,964/44,964 (100%) | PII script ran `SET email = NULL` before hash completed |
| `shopify_live_customers` | `first_name` | 44,964/44,964 (100%) | Same — wiped before hashing |
| `shopify_live_customers` | `last_name` | 44,964/44,964 (100%) | Same |
| `shopify_live_customers` | `phone` | 44,964/44,964 (100%) | Same |
| `shopify_live_orders` | `email` | 42,575/42,575 (100%) | Same PII script |
| `shopify_live_orders` | `phone` | 42,575/42,575 (100%) | Same |
| `shopify_live_orders` | `browser_ip` | 42,575/42,575 (100%) | Same — IP treated as PII |
| `shopify_live_orders` | `contact_email` | 42,575/42,575 (100%) | Same |

**Downstream impact on `_clean` tables:**

| Table | Field | NULL rate | Expected |
|-------|-------|-----------|----------|
| `shopify_live_customers_clean` | `email_hash` | 14,026/23,624 **(59% NULL)** | Should be ~0% |
| `shopify_live_customers_clean` | `first_name_hash` | 23,494/23,624 **(99.5% NULL)** | Should be ~5% |
| `shopify_live_customers_clean` | `last_name_hash` | 23,494/23,624 **(99.5% NULL)** | Should be ~5% |
| `shopify_live_customers_clean` | `phone_hash` | 23,494/23,624 **(99.5% NULL)** | Should be ~30% |
| `shopify_live_orders_clean` | `email_hash` | 8,589/17,021 **(50.5% NULL)** | Should be ~2% |

**Root cause:** The PII scheduled query does:
1. `UPDATE ... SET email = NULL` (wipes raw data)
2. `INSERT INTO _clean ... SHA256(email)` (tries to hash, but email is already NULL)

**Fix:** Reverse the order — hash first into `_clean`, THEN nullify in raw table. Or better: hash in a single pass `INSERT INTO _clean SELECT SHA256(email) ... FROM raw WHERE email IS NOT NULL`.

**Business impact:** Cannot join `orders ↔ customers` via email_hash for 50-59% of records. Cross-table analytics broken.

---

### BUG 2: TikTok view reads wrong columns (MEDIUM)

| View | Field | NULL rate | What happened |
|------|-------|-----------|---------------|
| `tiktok_ads_reports_daily` | `campaign_id` | 30,721/30,721 **(100%)** | View reads column, data is in JSON |
| `tiktok_ads_reports_daily` | `adgroup_id` | 30,721/30,721 **(100%)** | Same |
| `tiktok_ads_reports_daily` | `advertiser_id` | 30,721/30,721 **(100%)** | Column AND JSON both NULL (see API design below) |

**Root cause:** The Airbyte TikTok connector stores `campaign_id` and `adgroup_id` inside the `metrics` JSON blob, but also creates empty top-level columns. The view `tiktok_ads_reports_daily` reads the empty top-level columns.

**Proof:**
```
Top-level column campaign_id:  100% NULL (61,854/61,854)
JSON metrics.campaign_id:      100% filled (61,854/61,854)  ← data exists here
JSON metrics.adgroup_id:       100% filled (61,854/61,854)  ← data exists here
```

**Fix:** Change view to read from JSON:
```sql
-- BEFORE (broken):
SELECT campaign_id, adgroup_id, ...
-- AFTER (fixed):
SELECT
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.campaign_id') AS INT64) AS campaign_id,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.adgroup_id') AS INT64) AS adgroup_id,
  ...
```

**Business impact:** Cannot group TikTok ad performance by campaign or ad group. Campaign name lookups via `tiktok_campaigns` table are broken.

---

### BUG 3: Facebook 2024 missing reach/frequency/cpp (LOW)

| View | Fields | NULL rate | What happened |
|------|--------|-----------|---------------|
| `facebook_insights` | `reach`, `frequency`, `cpp` | 42,462/42,462 **(100% for 2024 data)** | Old Airbyte config didn't request these fields |

**Pattern:**
```
2024: reach 100% NULL (42,462 rows) — old sync config
2025: reach  2.4% NULL  (1,758 rows) — fixed after Job 150
2026: reach  0% NULL        (0 rows) — fully working
```

**Root cause:** The original Airbyte Facebook connector configuration didn't include `reach`, `frequency`, or `cpp` in the requested fields. After Job 150 reconfigured the connector, these fields started populating for 2025+ data.

**Fix:** Re-sync 2024 data with current config (requires Airbyte historical sync). Low priority since 2024 is historical.

**Business impact:** Cannot calculate reach/frequency for 2024 campaigns. 2025-2026 data is fine.

---

## API NEVER SENDS — Safe to exclude from views

These fields are 100% NULL because the Shopify/Facebook/TikTok API does not return them for this store's configuration. This is NOT a bug.

### Shopify Orders (42,575 rows)

| Field | NULL rate | Why API doesn't send |
|-------|-----------|---------------------|
| `company` | 100% | B2C store, no B2B orders — Shopify only fills for B2B |
| `po_number` | 100% | Purchase order numbers — B2B only feature |
| `device_id` | 100% | Deprecated by Shopify in 2023, always NULL for new syncs |
| `deleted_at` | 100% | Shopify doesn't actually delete orders, only archives |
| `payment_terms` | 99.99% (6 filled) | Only for draft/B2B orders with payment terms |
| `landing_site_ref` | 99.99% (4 filled) | Deprecated field, replaced by UTM tracking |
| `user_id` | 98% NULL | Internal Shopify staff user who created the order — only POS/manual orders |

### Shopify Customers (44,964 rows)

| Field | NULL rate | Why API doesn't send |
|-------|-----------|---------------------|
| `accepts_marketing` | 100% | Deprecated in Shopify API v2024-01+, replaced by `email_marketing_consent` |
| `multipass_identifier` | 100% | Enterprise SSO feature — not used by this store |
| `marketing_opt_in_level` | 100% | Deprecated, replaced by consent objects |

### Shopify Transactions (59,682 rows)

| Field | NULL rate | Why API doesn't send |
|-------|-----------|---------------------|
| `message` | 100% | Shopify payment gateway doesn't populate response messages |
| `device_id` | 100% | Deprecated field |
| `user_id` | 100% | Only for POS transactions (staff user) |
| `location_id` | 100% | Only for POS transactions (physical location) |

### TikTok (61,854 raw rows)

| Field | NULL rate | Why API doesn't send |
|-------|-----------|---------------------|
| `advertiser_id` (in metrics JSON) | 100% | TikTok ad-level reports don't include advertiser_id — it's a request parameter, not a response field |

---

## EXPECTED — NULL is normal business logic

These NULLs are correct and expected. A NULL here means the event didn't happen or doesn't apply.

### Shopify Orders

| Field | NULL rate | Why it's expected |
|-------|-----------|-------------------|
| `cancelled_at` | 99.7% (42,428/42,575) | Most orders are NOT cancelled. NULL = not cancelled. |
| `fulfillment_status` | 4.9% (2,072/42,575) | NULL = order is pending fulfillment. Normal for recent orders. |
| `cancel_reason` | 99.7% | Only filled when `cancelled_at` is not NULL |
| `closed_at` | 93.8% (2,633 filled) | Only filled for completed+archived orders |
| `note` | 99.8% (78 filled) | Customer notes are rare — most orders have no note |
| `source_url` | 69.7% NULL | Only filled for orders from external sources (API, marketplaces) |
| `checkout_token` | 31.5% NULL | NULL for API-created orders (Amazon, etc.) that skip Shopify checkout |

### Shopify Customers

| Field | NULL rate | Why it's expected |
|-------|-----------|-------------------|
| `last_order_id` | 30.7% (13,816/44,964) | Customers who signed up but never ordered |
| `last_order_name` | 30.7% | Same as above |
| `sms_marketing_consent` | 66.0% (29,680/44,964) | Only filled when customer interacted with SMS marketing |
| `note` | 99.7% | Staff notes on customers are rare |

### Shopify UTM (594,988 rows)

| Field | NULL rate | Why it's expected |
|-------|-----------|-------------------|
| `first_utm_source` | 79.2% (471,005) | Direct/organic/Amazon orders have no UTM tags. Only 20.8% of orders come from tracked ad campaigns. |
| `first_utm_medium` | 79.2% (471,127) | Same — no UTM = no medium |
| `first_utm_campaign` | 83.8% (498,530) | Some UTM-tagged orders have source but no campaign name |
| `first_utm_content` | 83.9% (499,033) | Ad content tag is optional in UTM |
| `first_utm_term` | 86.7% (515,645) | Search term — only for search ads |
| `days_to_conversion` | 42.1% (250,580) | Only calculable when first visit timestamp exists |
| `first_landing_page` | 42.6% (253,361) | Only for orders with a tracked first visit |
| `sales_channel` | 4.5% (26,621) | Some orders have no channel assignment |

### Facebook Insights (128,345 rows)

| Field | NULL rate | Why it's expected |
|-------|-----------|-------------------|
| `cpc` (excluding 2024 bug) | 16.3% (17,587/107,704 with spend>0) | NULL when clicks = 0. Cannot divide spend by zero clicks. |
| `cpm` | 0% (when spend>0) | Always calculable when there are impressions |
| `ctr` | 0% (when spend>0) | Always calculable when there are impressions |
| `impressions` | 222 NULL (0.2%) | Rows with zero_spend — ad was paused, no impressions recorded |

### Shopify Bulk Orders (585,927 rows) — CLEANEST TABLE

| Field | NULL rate | Note |
|-------|-----------|------|
| `shipping_zip` | 377/585,927 (0.06%) | Digital/pickup orders with no shipping |
| `email_hash` | 173/585,927 (0.03%) | Guest checkout without email |
| All other fields | 0% | Fully populated |

---

## Action items

### URGENT (breaks analytics)

| # | Bug | Fix | Impact |
|---|-----|-----|--------|
| 1 | PII script order-of-operations | Hash first, nullify second | Restores 50-59% of email_hash joins |
| 2 | TikTok view wrong columns | Read campaign_id/adgroup_id from `metrics` JSON | Enables campaign-level TikTok reporting |

### LOW PRIORITY

| # | Bug | Fix | Impact |
|---|-----|-----|--------|
| 3 | Facebook 2024 reach data | Re-sync 2024 with current Airbyte config | Historical reach/frequency for 2024 |

### NO ACTION (safe to remove from `ads_analyst` views)

These 14 fields should be excluded from `ads_analyst` views because they are always NULL by API design:

`company`, `po_number`, `device_id`, `deleted_at`, `payment_terms`, `landing_site_ref`, `accepts_marketing`, `multipass_identifier`, `marketing_opt_in_level`, `message` (transactions), `device_id` (transactions), `user_id` (transactions), `location_id` (transactions), `advertiser_id` (TikTok metrics)

---

*Audit based on live BigQuery data as of 2026-02-12.*
