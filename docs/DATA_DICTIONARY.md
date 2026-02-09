# Data Dictionary & Analysis Reference

> Better Signal - `hulken.ads_data` BigQuery Dataset
> Generated: 8 February 2026
> Total: 49 tables, ~9.4 GB, ~4.8M rows

---

## Table of Contents

1. [Table Inventory](#1-table-inventory)
2. [Core Tables - Column Reference](#2-core-tables---column-reference)
3. [Join Keys & Relationships](#3-join-keys--relationships)
4. [Dedup Views](#4-dedup-views)
5. [Analysis Queries](#5-analysis-queries)
6. [Noise Audit - Tables & Columns to Clean](#6-noise-audit---tables--columns-to-clean)
7. [Data Type Gotchas](#7-data-type-gotchas)

---

## 1. Table Inventory

### Shopify (9 tables, ~620 MB)

| Table | Rows | Size | Purpose | Sync |
|-------|------|------|---------|------|
| `shopify_orders` | 585,927 | 160 MB | Historical orders (GraphQL bulk export), email_hash | Manual extract |
| `shopify_utm` | 592,091 | 128 MB | UTM attribution per order (custom script) | Custom script |
| `shopify_live_orders` | 12,959 | 99 MB | Live orders via Airbyte, PII **nullified** | Airbyte 24h |
| `shopify_live_orders_clean` | 12,959 | 52 MB | Same but with email_hash/phone_hash | Scheduled query 5min |
| `shopify_live_customers` | 17,794 | 5 MB | Live customers via Airbyte, PII **nullified** | Airbyte 24h |
| `shopify_live_customers_clean` | 17,794 | 7 MB | Same but with email_hash/phone_hash | Scheduled query 5min |
| `shopify_live_transactions` | 38,990 | 115 MB | Payment transactions | Airbyte 24h |
| `shopify_live_products` | 977 | 2 MB | Product catalog | Airbyte 24h |
| `shopify_live_order_refunds` | 410 | 2 MB | Refund records | Airbyte 24h |
| `shopify_line_items` | 719,124 | 79 MB | Order line items (historical) | Manual extract |

### Facebook - Primary (4 tables + 4 dedup views, ~6.4 GB)

| Table | Rows | Size | Purpose | Sync |
|-------|------|------|---------|------|
| `facebook_ads_insights` | 159,342 | 820 MB | Daily ad performance (append mode, **use dedup view**) | Airbyte 24h |
| `facebook_ads_insights_age_and_gender` | 1,494,810 | 3.6 GB | Performance by age+gender | Airbyte 24h |
| `facebook_ads_insights_country` | 332,442 | 1.1 GB | Performance by country | Airbyte 24h |
| `facebook_ads_insights_region` | 911,412 | 862 MB | Performance by region | Airbyte 24h |
| `facebook_ad_creatives` | 5,160 | 13 MB | Creative assets (image URLs, copy, CTA) | Airbyte 24h |
| `facebook_ads` | 5,428 | 7 MB | Ad metadata | Airbyte 24h |
| `facebook_ad_sets` | 341 | 0.2 MB | Ad set configuration | Airbyte 24h |

### Facebook - Legacy DUPLICATES (7 tables, ~2.2 GB) - SEE NOISE AUDIT

| Table | Rows | Size | Duplicate Of |
|-------|------|------|-------------|
| `ads_insights` | 33,433 | 122 MB | `facebook_ads_insights` (fewer rows) |
| `ads_insights_age_and_gender` | 245,941 | 462 MB | `facebook_ads_insights_age_and_gender` |
| `ads_insights_country` | 105,734 | 246 MB | `facebook_ads_insights_country` |
| `ads_insights_region` | 704,120 | 630 MB | `facebook_ads_insights_region` |
| `ads_insights_platform_and_device` | 467,829 | 568 MB | No facebook_ equivalent |
| `ads_insights_action_type` | 33,434 | 103 MB | No facebook_ equivalent |
| `ads_insights_dma` | 26,415 | 50 MB | No facebook_ equivalent |
| `ad_creatives` | 3,483 | 9 MB | `facebook_ad_creatives` |
| `ad_sets` | 62 | 0 MB | `facebook_ad_sets` |
| `ads` | 1,172 | 2 MB | `facebook_ads` |
| `campaigns` | - | - | No facebook_ equivalent |
| `images` | 342 | 0.5 MB | No facebook_ equivalent |

### TikTok (22 tables, ~830 MB)

**Primary tables (use these):**

| Table | Rows | Size | Purpose |
|-------|------|------|---------|
| `tiktokads_reports_daily` | 30,287 | 26 MB | Daily ad-level performance (spend, metrics in JSON) |
| `tiktokcampaigns` | 35 | 0 MB | Campaign metadata (name, budget, status) |
| `tiktokad_groups` | 71 | 0.1 MB | Ad group metadata |
| `tiktokads` | 854 | 0.6 MB | Ad metadata |

**Audience breakdown tables (granular views):**

| Table | Rows | Size | Breakdown |
|-------|------|------|-----------|
| `tiktokads_audience_reports_by_province_daily` | 1,052,020 | 552 MB | Province + age + gender |
| `tiktokads_audience_reports_daily` | 230,288 | 118 MB | Age + gender |
| `tiktokads_audience_reports_by_platform_daily` | 89,294 | 46 MB | Platform (iOS/Android) |
| `tiktokads_audience_reports_by_country_daily` | 33,383 | 17 MB | Country |
| `tiktokads_reports_by_country_daily` | 34,444 | 27 MB | Country (no audience) |

**Redundant aggregation tables (campaign/adgroup/advertiser level):**

| Table | Rows | Size | Notes |
|-------|------|------|-------|
| `tiktokcampaigns_reports_daily` | 5,777 | 2 MB | Campaign-level daily |
| `tiktokcampaigns_audience_reports_daily` | 50,725 | 10 MB | Campaign audience |
| `tiktokcampaigns_audience_reports_by_platform_daily` | 17,852 | 3 MB | Campaign by platform |
| `tiktokcampaigns_audience_reports_by_country_daily` | 6,109 | 1 MB | Campaign by country |
| `tiktokad_groups_reports_daily` | 6,673 | 3 MB | Ad group daily |
| `tiktokad_groups_reports_by_country_daily` | 7,250 | 3 MB | Ad group by country |
| `tiktokad_group_audience_reports_daily` | 53,813 | 18 MB | Ad group audience |
| `tiktokad_group_audience_reports_by_platform_daily` | 19,751 | 6 MB | Ad group by platform |
| `tiktokad_group_audience_reports_by_country_daily` | 6,863 | 2 MB | Ad group by country |
| `tiktokadvertisers_reports_daily` | 1,331 | 0.4 MB | Advertiser daily |
| `tiktokadvertisers_audience_reports_daily` | 17,315 | 3 MB | Advertiser audience |
| `tiktokadvertisers_audience_reports_by_platform_daily` | 4,982 | 0.7 MB | Advertiser by platform |
| `tiktokadvertisers_audience_reports_by_country_daily` | 1,785 | 0.3 MB | Advertiser by country |

---

## 2. Core Tables - Column Reference

### `shopify_utm` - UTM Attribution (THE table for ROAS analysis)

| Column | Type | Description |
|--------|------|-------------|
| `order_id` | STRING | Shopify order ID (joins to `shopify_orders.id` via `gid://shopify/Order/{id}` format) |
| `order_name` | STRING | Human-readable order number (#1001, #1002...) |
| `created_at` | TIMESTAMP | Order creation date (**DATETIME-like, use DATE() to compare**) |
| `total_price` | FLOAT64 | Order total in dollars |
| `customer_order_index` | INT64 | 1 = first order (new customer), 2+ = repeat |
| `days_to_conversion` | INT64 | Days between first visit and purchase |
| `first_utm_source` | STRING | First-touch source (facebook-fb, facebook-ig, google, klaviyo, tiktok...) |
| `first_utm_medium` | STRING | First-touch medium (paid, cpc, email...) |
| `first_utm_campaign` | STRING | First-touch campaign name (**joins to facebook/tiktok campaign_name**) |
| `first_utm_content` | STRING | First-touch ad content identifier |
| `first_utm_term` | STRING | First-touch keyword/term |
| `first_landing_page` | STRING | First page visited |
| `first_referrer_url` | STRING | Referrer URL of first visit |
| `first_visit_at` | TIMESTAMP | Timestamp of first visit |
| `last_utm_source` | STRING | Last-touch source before purchase |
| `last_utm_medium` | STRING | Last-touch medium |
| `last_utm_campaign` | STRING | Last-touch campaign |
| `last_landing_page` | STRING | Last page before purchase |
| `last_visit_at` | TIMESTAMP | Last visit timestamp |
| `sales_channel` | STRING | Shopify sales channel |
| `sales_channel_name` | STRING | Channel display name |
| `sales_channel_app` | STRING | Channel app identifier |
| `attribution_status` | STRING | Attribution quality flag |
| `extracted_at` | TIMESTAMP | When this row was extracted |

**No Airbyte columns. No PII. No email_hash (use shopify_orders for that).**

### `shopify_orders` - Historical Orders with Email Hash

| Column | Type | Description |
|--------|------|-------------|
| `id` | STRING | GraphQL GID (`gid://shopify/Order/123456`) |
| `name` | STRING | Order name (#1001) - **joins to shopify_utm.order_name** |
| `createdAt` | TIMESTAMP | Order date (camelCase!) |
| `processedAt` | TIMESTAMP | Payment processed date |
| `currencyCode` | STRING | Currency (CAD, USD, EUR) |
| `displayFinancialStatus` | STRING | PAID, REFUNDED, PARTIALLY_REFUNDED |
| `displayFulfillmentStatus` | STRING | FULFILLED, UNFULFILLED |
| `totalPrice` | FLOAT64 | Order total (camelCase!) |
| `subtotalPrice` | FLOAT64 | Before tax/shipping |
| `totalTax` | FLOAT64 | Tax amount |
| `totalDiscounts` | FLOAT64 | Discount amount |
| `customer_id` | STRING | Customer GID |
| `shipping_country` | STRING | Country code |
| `shipping_city` | STRING | City |
| `shipping_zip` | STRING | Postal code |
| `email_hash` | STRING | SHA-256 hash (**the key for LTV analysis**) |

**No Airbyte columns. email_hash pre-computed during extraction.**

### `facebook_ads_insights` (USE `_dedup` VIEW) - Ad Performance

| Column | Type | Key For |
|--------|------|---------|
| `ad_id` | STRING | Ad identifier (joins to facebook_ads.id, ad_creatives) |
| `ad_name` | STRING | Ad display name |
| `adset_id` | STRING | Ad set identifier |
| `adset_name` | STRING | Ad set display name |
| `campaign_id` | STRING | Campaign identifier |
| `campaign_name` | STRING | **Joins to shopify_utm.first_utm_campaign** |
| `account_id` | STRING | Ad account ID |
| `account_name` | STRING | Account display name |
| `date_start` | DATE | Reporting date |
| `date_stop` | DATE | Always = date_start (daily granularity) |
| `spend` | NUMERIC | Daily spend in dollars |
| `impressions` | INT64 | Impression count |
| `reach` | INT64 | Unique people reached |
| `clicks` | INT64 | All clicks |
| `unique_clicks` | INT64 | Unique clicks |
| `cpc` | NUMERIC | Cost per click |
| `cpm` | NUMERIC | Cost per 1000 impressions |
| `ctr` | NUMERIC | Click-through rate |
| `frequency` | NUMERIC | Average times shown per person |
| `actions` | JSON | Array of action objects `[{action_type, value}]` |
| `action_values` | JSON | Array of action value objects `[{action_type, value}]` |
| `conversions` | JSON | Conversion actions |
| `conversion_values` | JSON | Conversion monetary values |
| `purchase_roas` | JSON | Facebook-reported ROAS |
| `objective` | STRING | Campaign objective |
| `optimization_goal` | STRING | Optimization target |
| `quality_ranking` | STRING | Ad quality score |
| `inline_link_clicks` | INT64 | Clicks to destination |
| `outbound_clicks` | JSON | Clicks leaving Facebook |
| `video_play_actions` | JSON | Video view metrics |
| `social_spend` | NUMERIC | Social context spend |

**Also present in `_age_and_gender`, `_country`, `_region` tables with extra dimension columns.**

Extra columns in demographic tables:
- `age_and_gender`: + `age` (STRING), `gender` (STRING)
- `country`: + `country` (STRING)
- `region`: + `region` (STRING)

### `tiktokads_reports_daily` - TikTok Ad Performance

| Column | Type | Description |
|--------|------|-------------|
| `ad_id` | INT64 | Ad identifier (joins to tiktokads.ad_id) |
| `adgroup_id` | INT64 | Ad group (joins to tiktokad_groups) |
| `campaign_id` | INT64 | Campaign (joins to tiktokcampaigns.campaign_id) |
| `advertiser_id` | INT64 | Advertiser account |
| `stat_time_day` | DATETIME | Reporting date (**DATETIME not DATE, use DATE() to compare**) |
| `stat_time_hour` | DATETIME | Hourly timestamp (usually null for daily) |
| `metrics` | JSON | **All metrics are nested in this JSON blob** |
| `dimensions` | JSON | Dimension metadata |

**Extracting TikTok metrics from JSON:**
```sql
CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64) AS spend
CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64) AS impressions
CAST(JSON_EXTRACT_SCALAR(metrics, '$.clicks') AS INT64) AS clicks
CAST(JSON_EXTRACT_SCALAR(metrics, '$.conversion') AS INT64) AS conversions
CAST(JSON_EXTRACT_SCALAR(metrics, '$.complete_payment') AS INT64) AS purchases
CAST(JSON_EXTRACT_SCALAR(metrics, '$.total_complete_payment_rate') AS FLOAT64) AS conv_rate
```

### `tiktokcampaigns` - Campaign Metadata

| Column | Type | Description |
|--------|------|-------------|
| `campaign_id` | INT64 | PK - joins to reports |
| `campaign_name` | STRING | **Joins to shopify_utm.first_utm_campaign** |
| `budget` | FLOAT64 | Campaign budget |
| `budget_mode` | STRING | BUDGET_MODE_DAY / BUDGET_MODE_TOTAL |
| `objective_type` | STRING | PRODUCT_SALES, etc. |
| `status` | STRING | ENABLE / DISABLE |

### `shopify_live_orders_clean` - Live Orders (PII Safe)

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT64 | Shopify order numeric ID |
| `name` | STRING | Order name (#BS1001) |
| `email_hash` | STRING | SHA-256 of email (**added by scheduled query**) |
| `phone_hash` | STRING | SHA-256 of phone (**added by scheduled query**) |
| `total_price` | NUMERIC | Order total |
| `subtotal_price` | NUMERIC | Before tax |
| `total_tax` | NUMERIC | Tax |
| `currency` | STRING | Currency code |
| `created_at` | TIMESTAMP | Order date |
| `financial_status` | STRING | paid, refunded, etc. |
| `fulfillment_status` | STRING | fulfilled, etc. |
| `tags` | STRING | Order tags |
| `discount_codes` | JSON | Applied discounts |
| `line_items` | JSON | Order items |
| `shipping_lines` | JSON | Shipping info |
| `customer` | JSON | Customer object (PII nullified inside) |

**PII columns removed:** email, phone, browser_ip, contact_email, first_name, last_name
**PII columns added:** email_hash, phone_hash

### `shopify_live_customers_clean` - Live Customers (PII Safe)

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT64 | Shopify customer ID |
| `email_hash` | STRING | SHA-256 of email |
| `phone_hash` | STRING | SHA-256 of phone (null = never provided) |
| `state` | STRING | Customer state (disabled, enabled) |
| `tags` | STRING | Customer tags |
| `total_spent` | NUMERIC | Lifetime spend |
| `orders_count` | INT64 | Total order count |
| `created_at` | TIMESTAMP | Account creation date |
| `updated_at` | TIMESTAMP | Last update |
| `verified_email` | BOOL | Email verified |
| `accepts_marketing` | BOOL | Marketing opt-in |
| `last_order_id` | INT64 | Most recent order ID |
| `last_order_name` | STRING | Most recent order name |

---

## 3. Join Keys & Relationships

```
shopify_utm.first_utm_campaign ──────► facebook_ads_insights_dedup.campaign_name
                                       (22/38 campaigns match, 58%)

shopify_utm.first_utm_campaign ──────► tiktokcampaigns.campaign_name
                                       (34/34 campaigns match, 100%)

shopify_utm.order_name ─────────────► shopify_orders.name
                                       (for email_hash lookup)

shopify_orders.email_hash ──────────► shopify_live_customers_clean.email_hash
                                       (75% match, 25% = guest checkout)

shopify_live_orders_clean.id ───────► shopify_live_customers_clean.last_order_id

facebook_ads_insights.ad_id ────────► facebook_ad_creatives.id
                                       (creative content lookup)

facebook_ads_insights.campaign_id ──► campaigns.id (or via campaign_name)

tiktokads_reports_daily.campaign_id ► tiktokcampaigns.campaign_id

tiktokads_reports_daily.ad_id ──────► tiktokads.ad_id

tiktokads_reports_daily.adgroup_id ─► tiktokad_groups.adgroup_id
```

### Cross-Platform Customer Matching

```
shopify_utm (has order_name, no email_hash)
    │
    ├─ JOIN shopify_orders ON order_name = name
    │    └─ Gets email_hash
    │
    └─ email_hash links to:
         ├─ shopify_live_customers_clean (customer profile)
         └─ All other orders by same customer (LTV)
```

---

## 4. Dedup Views

Facebook data arrives in **append mode** causing ~20.9% duplicates. Always use these views:

| View | Base Table | Dedup Key | Clean Rows |
|------|-----------|-----------|------------|
| `facebook_ads_insights_dedup` | facebook_ads_insights | ad_id, date_start, account_id | 126,089 |
| `facebook_ads_insights_age_and_gender_dedup` | facebook_ads_insights_age_and_gender | ad_id, date_start, account_id, age, gender | ~1.2M |
| `facebook_ads_insights_country_dedup` | facebook_ads_insights_country | ad_id, date_start, account_id, country | ~263K |
| `facebook_ads_insights_region_dedup` | facebook_ads_insights_region | ad_id, date_start, account_id, region | ~720K |

**Dedup SQL pattern used:**
```sql
CREATE OR REPLACE VIEW `hulken.ads_data.facebook_ads_insights_dedup` AS
SELECT * EXCEPT(rn) FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY ad_id, date_start, account_id
    ORDER BY _airbyte_extracted_at DESC
  ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights`
) WHERE rn = 1
```

**RULE: Never query raw `facebook_ads_insights` tables directly. Always use `_dedup` views.**

---

## 5. Analysis Queries

### A. ROAS by Facebook Campaign

```sql
-- Facebook campaign ROAS using first-touch attribution
SELECT
  u.first_utm_campaign AS campaign,
  COUNT(DISTINCT u.order_id) AS orders,
  ROUND(SUM(u.total_price), 2) AS revenue,
  f.spend,
  ROUND(SUM(u.total_price) / NULLIF(f.spend, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT campaign_name, ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend
  FROM `hulken.ads_data.facebook_ads_insights_dedup`
  GROUP BY 1
) f ON u.first_utm_campaign = f.campaign_name
WHERE u.first_utm_source LIKE '%facebook%'
GROUP BY 1, f.spend
ORDER BY revenue DESC
```

### B. ROAS by TikTok Campaign

```sql
-- TikTok campaign ROAS using first-touch attribution
SELECT
  u.first_utm_campaign AS campaign,
  COUNT(DISTINCT u.order_id) AS orders,
  ROUND(SUM(u.total_price), 2) AS revenue,
  t.spend,
  ROUND(SUM(u.total_price) / NULLIF(t.spend, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT c.campaign_name,
    ROUND(SUM(CAST(JSON_EXTRACT_SCALAR(r.metrics, '$.spend') AS FLOAT64)), 2) AS spend
  FROM `hulken.ads_data.tiktokads_reports_daily` r
  JOIN `hulken.ads_data.tiktokcampaigns` c ON r.campaign_id = c.campaign_id
  GROUP BY 1
) t ON u.first_utm_campaign = t.campaign_name
WHERE u.first_utm_source = 'tiktok'
GROUP BY 1, t.spend
ORDER BY revenue DESC
```

### C. Customer Acquisition Cost (CAC) by Channel

```sql
-- New customer acquisition by channel (customer_order_index = 1)
SELECT
  first_utm_source AS channel,
  COUNT(DISTINCT order_id) AS new_customers,
  ROUND(SUM(total_price), 2) AS first_order_revenue,
  ROUND(SUM(total_price) / COUNT(DISTINCT order_id), 2) AS avg_first_order,
  ROUND(AVG(days_to_conversion), 1) AS avg_days_to_convert
FROM `hulken.ads_data.shopify_utm`
WHERE customer_order_index = 1
GROUP BY 1
ORDER BY new_customers DESC
```

### D. Lifetime Value by Acquisition Channel

```sql
-- LTV analysis: which channels bring the most valuable customers?
WITH first_touch AS (
  SELECT order_id, first_utm_source AS acquisition_channel
  FROM `hulken.ads_data.shopify_utm`
  WHERE customer_order_index = 1
),
customer_ltv AS (
  SELECT
    o_first.customer_id,
    ft.acquisition_channel,
    COUNT(DISTINCT o_all.id) AS total_orders,
    SUM(o_all.totalPrice) AS lifetime_revenue
  FROM first_touch ft
  JOIN `hulken.ads_data.shopify_orders` o_first ON CONCAT('gid://shopify/Order/', ft.order_id) = o_first.id
  JOIN `hulken.ads_data.shopify_orders` o_all ON o_first.customer_id = o_all.customer_id
  GROUP BY 1, 2
)
SELECT
  acquisition_channel,
  COUNT(*) AS customers,
  ROUND(AVG(total_orders), 1) AS avg_orders,
  ROUND(SUM(lifetime_revenue), 2) AS total_ltv,
  ROUND(SUM(lifetime_revenue) / COUNT(*), 2) AS avg_ltv
FROM customer_ltv
GROUP BY 1
ORDER BY total_ltv DESC
```

### E. First-Touch vs Last-Touch Attribution

```sql
-- Shows where first touch ≠ last touch (multi-touch journeys)
SELECT
  first_utm_source AS first_touch_channel,
  last_utm_source AS last_touch_channel,
  COUNT(*) AS conversions,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_source IS NOT NULL
  AND last_utm_source IS NOT NULL
  AND first_utm_source != last_utm_source
GROUP BY 1, 2
HAVING conversions >= 10
ORDER BY revenue DESC
```

### F. Daily Blended ROAS (Cross-Platform)

```sql
-- Daily cross-platform spend vs revenue
WITH daily_spend AS (
  SELECT date_start AS dt,
    ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS fb_spend
  FROM `hulken.ads_data.facebook_ads_insights_dedup`
  GROUP BY 1
),
daily_tiktok AS (
  SELECT DATE(stat_time_day) AS dt,
    ROUND(SUM(CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64)), 2) AS tt_spend
  FROM `hulken.ads_data.tiktokads_reports_daily`
  GROUP BY 1
),
daily_revenue AS (
  SELECT DATE(created_at) AS dt,
    ROUND(SUM(total_price), 2) AS revenue,
    COUNT(*) AS orders
  FROM `hulken.ads_data.shopify_utm`
  GROUP BY 1
)
SELECT
  r.dt,
  COALESCE(r.revenue, 0) AS revenue,
  COALESCE(r.orders, 0) AS orders,
  COALESCE(f.fb_spend, 0) AS facebook_spend,
  COALESCE(t.tt_spend, 0) AS tiktok_spend,
  COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0) AS total_spend,
  ROUND(COALESCE(r.revenue, 0) / NULLIF(COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0), 0), 2) AS blended_roas
FROM daily_revenue r
LEFT JOIN daily_spend f ON r.dt = f.dt
LEFT JOIN daily_tiktok t ON r.dt = t.dt
WHERE r.dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY r.dt DESC
```

### G. Facebook Age/Gender Performance

```sql
-- Which demographics convert best?
SELECT
  age, gender,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SUM(CAST(spend AS FLOAT64)) / NULLIF(SUM(clicks), 0), 2) AS cost_per_click,
  ROUND(SUM(CAST(ctr AS FLOAT64) * impressions) / NULLIF(SUM(impressions), 0), 4) AS weighted_ctr
FROM `hulken.ads_data.facebook_ads_insights_age_and_gender_dedup`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
HAVING spend > 100
ORDER BY spend DESC
```

### H. Sync Freshness Check

```sql
-- Quick health check: are all tables up to date?
SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS hours_behind,
  row_count,
  ROUND(size_bytes / 1048576, 1) AS size_mb
FROM `hulken.ads_data.__TABLES__`
WHERE table_id IN (
  'facebook_ads_insights', 'tiktokads_reports_daily',
  'shopify_live_orders', 'shopify_live_customers',
  'shopify_live_orders_clean', 'shopify_live_customers_clean',
  'shopify_utm'
)
ORDER BY hours_behind DESC
```

### I. PII Compliance Check

```sql
-- Verify no plaintext PII leaks in clean tables
SELECT 'orders_clean' AS table_name,
  COUNTIF(email_hash IS NOT NULL AND LENGTH(email_hash) = 64) AS valid_hashes,
  COUNTIF(email_hash IS NOT NULL AND LENGTH(email_hash) != 64) AS invalid_hashes,
  COUNT(*) AS total
FROM `hulken.ads_data.shopify_live_orders_clean`
UNION ALL
SELECT 'customers_clean',
  COUNTIF(email_hash IS NOT NULL AND LENGTH(email_hash) = 64),
  COUNTIF(email_hash IS NOT NULL AND LENGTH(email_hash) != 64),
  COUNT(*)
FROM `hulken.ads_data.shopify_live_customers_clean`
```

### J. Facebook Duplicate Detection

```sql
-- Check current duplicate rate
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT CONCAT(ad_id, '|', CAST(date_start AS STRING), '|', account_id)) AS unique_keys,
  COUNT(*) - COUNT(DISTINCT CONCAT(ad_id, '|', CAST(date_start AS STRING), '|', account_id)) AS duplicates,
  ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT CONCAT(ad_id, '|', CAST(date_start AS STRING), '|', account_id))) / COUNT(*), 1) AS dup_pct
FROM `hulken.ads_data.facebook_ads_insights`
```

---

## 6. Noise Audit - Tables & Columns to Clean

### PRIORITY 1: Duplicate Facebook Tables (2.2 GB wasted)

The `ads_*` prefix tables come from an older Airbyte connection and are **exact schema duplicates** of the `facebook_*` tables but with **fewer rows** (less complete data).

| Delete | Keep | Savings |
|--------|------|---------|
| `ads_insights` (33K rows) | `facebook_ads_insights` (159K rows) | 122 MB |
| `ads_insights_age_and_gender` (246K) | `facebook_ads_insights_age_and_gender` (1.5M) | 462 MB |
| `ads_insights_country` (106K) | `facebook_ads_insights_country` (332K) | 246 MB |
| `ads_insights_region` (704K) | `facebook_ads_insights_region` (911K) | 630 MB |
| `ad_creatives` (3.5K) | `facebook_ad_creatives` (5.2K) | 9 MB |
| `ad_sets` (62) | `facebook_ad_sets` (341) | 0 MB |
| `ads` (1.2K) | `facebook_ads` (5.4K) | 2 MB |

**Unique to old connection (review before deleting):**

| Table | Rows | Size | Action |
|-------|------|------|--------|
| `ads_insights_platform_and_device` | 467,829 | 568 MB | **KEEP** - no facebook_ equivalent, useful for device targeting analysis |
| `ads_insights_action_type` | 33,434 | 103 MB | **KEEP** - no facebook_ equivalent, action type breakdown |
| `ads_insights_dma` | 26,415 | 50 MB | **KEEP** - no facebook_ equivalent, US DMA geo data |
| `campaigns` | - | - | **KEEP** - campaign metadata (no facebook_campaigns table exists) |
| `images` | 342 | 0.5 MB | Review - may be referenced by ad_creatives |

**Recommended action:** Delete 7 duplicate tables, save ~1.5 GB. Keep 5 unique tables.

### PRIORITY 2: TikTok Table Explosion (13 redundant tables, ~47 MB)

The TikTok Airbyte connector creates separate tables for every combination of:
- Level: ads, ad_groups, campaigns, advertisers
- Report type: reports, audience_reports
- Breakdown: daily, by_country, by_platform, by_province

Most analysis only needs:
- `tiktokads_reports_daily` (ad-level spend/performance)
- `tiktokcampaigns` (campaign names)
- `tiktokads_audience_reports_by_province_daily` (geo analysis, if needed)

**Candidates to drop or ignore (all can be derived from ad-level data):**

| Table | Why Redundant |
|-------|--------------|
| `tiktokcampaigns_reports_daily` | = SUM of tiktokads_reports_daily grouped by campaign_id |
| `tiktokad_groups_reports_daily` | = SUM of tiktokads_reports_daily grouped by adgroup_id |
| `tiktokadvertisers_reports_daily` | = SUM of tiktokads_reports_daily (one advertiser) |
| `tiktokcampaigns_audience_reports_*` (3 tables) | = SUM of ad-level audience reports |
| `tiktokad_group_audience_reports_*` (3 tables) | = SUM of ad-level audience reports |
| `tiktokadvertisers_audience_reports_*` (3 tables) | = SUM of ad-level audience reports |
| `tiktokads_reports_by_country_daily` | Overlaps with audience_reports_by_country |

**Recommended action:** Disable these streams in the Airbyte TikTok connector to stop ingesting them. Keep existing data for reference but stop syncing 13 unnecessary tables.

### PRIORITY 3: Airbyte Internal Columns (present in every Airbyte table)

Every table synced via Airbyte has 4 system columns:

| Column | Type | Purpose | For Analysis? |
|--------|------|---------|--------------|
| `_airbyte_raw_id` | STRING | Unique row ID | No |
| `_airbyte_extracted_at` | TIMESTAMP | When Airbyte extracted | Only for dedup |
| `_airbyte_meta` | JSON | Sync metadata | No |
| `_airbyte_generation_id` | INT64 | Sync generation | No |

**Recommended action:** Create analysis views that exclude these columns. Already done for Facebook (`_dedup` views). Consider doing the same for TikTok and Shopify live tables.

### PRIORITY 4: Noisy Columns in Shopify Live Orders

`shopify_live_orders` has 80+ columns. Many are empty or irrelevant for analytics:

| Column Category | Examples | Action |
|----------------|----------|--------|
| Deprecated Shopify fields | `token`, `reference`, `checkout_token`, `cart_token`, `device_id` | Ignore |
| Internal IDs | `app_id`, `user_id`, `checkout_id`, `location_id` | Ignore |
| Redundant price sets | `total_price_set`, `subtotal_price_set`, `total_tax_set`, `total_shipping_price_set`, `current_*` | Ignore (same data in different currency format) |
| Admin fields | `admin_graphql_api_id`, `source_name`, `source_url` | Ignore |
| Null/empty columns | `company`, `po_number`, `payment_terms`, `note` | Mostly null |

**Recommended action:** The `shopify_live_orders_clean` table already strips PII. Consider creating a `shopify_live_orders_analytics` view with only the 15-20 useful columns.

### PRIORITY 5: TikTok Metrics JSON Blob

All TikTok tables store metrics as a single JSON column, making queries verbose:
```sql
-- Current (verbose)
CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64)

-- Ideal (clean view)
spend  -- as a proper FLOAT64 column
```

**Recommended action:** Create a `tiktokads_reports_clean` view that extracts the top 10 metrics into proper columns.

**Proposed view:**
```sql
CREATE OR REPLACE VIEW `hulken.ads_data.tiktokads_reports_clean` AS
SELECT
  ad_id,
  adgroup_id,
  campaign_id,
  advertiser_id,
  DATE(stat_time_day) AS report_date,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64) AS spend,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64) AS impressions,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.clicks') AS INT64) AS clicks,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.conversion') AS INT64) AS conversions,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.complete_payment') AS INT64) AS purchases,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cost_per_conversion') AS FLOAT64) AS cost_per_conversion,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cpc') AS FLOAT64) AS cpc,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cpm') AS FLOAT64) AS cpm,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.ctr') AS FLOAT64) AS ctr,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.reach') AS INT64) AS reach
FROM `hulken.ads_data.tiktokads_reports_daily`
```

---

## 7. Data Type Gotchas

These caused errors during analysis. Keep this list for reference.

| Table | Column | Declared Type | Gotcha |
|-------|--------|--------------|--------|
| `shopify_utm` | `created_at` | TIMESTAMP | Behaves like DATETIME. Use `DATE(created_at)` for date comparisons |
| `shopify_utm` | `total_price` | FLOAT64 | Already FLOAT64, no need to CAST |
| `shopify_orders` | `totalPrice` | FLOAT64 | camelCase (GraphQL convention) |
| `shopify_orders` | `createdAt` | TIMESTAMP | camelCase |
| `shopify_live_orders` | `total_price` | NUMERIC | Need CAST to FLOAT64 for math |
| `facebook_ads_insights` | `spend` | NUMERIC | Need CAST to FLOAT64 for division |
| `facebook_ads_insights` | `date_start` | DATE | Proper DATE type, works with DATE_SUB |
| `tiktokads_reports_daily` | `stat_time_day` | DATETIME | Not DATE! Use `DATE(stat_time_day)` |
| `tiktokads_reports_daily` | `metrics` | JSON | All metrics buried in JSON, must use JSON_EXTRACT_SCALAR |
| `tiktokads_reports_daily` | `ad_id` | INT64 | INT64 not STRING (unlike Facebook which uses STRING) |
| `shopify_orders` | `id` | STRING | GraphQL GID format: `gid://shopify/Order/123456` |
| `shopify_utm` | `order_id` | STRING | Plain numeric string, NOT GID format |
| `shopify_live_orders` | `processed_at` | STRING | Should be TIMESTAMP but stored as STRING |

### Table Name Gotchas

| Wrong | Correct | Notes |
|-------|---------|-------|
| `tiktok_ads_reports_daily` | `tiktokads_reports_daily` | No underscore between tiktok and ads |
| `tiktok_campaigns` | `tiktokcampaigns` | All one word |
| `shopify_customers` | `shopify_live_customers` | Need `live_` prefix |
| `facebook_campaigns` | `campaigns` | Uses legacy `ads_` prefix naming |

### Column Name Gotchas

| Table | Wrong | Correct |
|-------|-------|---------|
| `shopify_utm` | `email_hash` | Does not exist. Join through `shopify_orders` |
| `shopify_utm` | `email` | Does not exist. No PII in this table |
| `shopify_live_orders` | `email` | Exists but **nullified** (PII protection) |
| `shopify_live_orders_clean` | `email` | Does not exist. Use `email_hash` |
| `shopify_orders` | `created_at` | It's `createdAt` (camelCase) |
| `shopify_orders` | `total_price` | It's `totalPrice` (camelCase) |

---

## Appendix: Airbyte Connection IDs

For manual sync triggers (run on Airbyte VM):

| Connection | ID | Sync Frequency |
|-----------|-----|----------------|
| Facebook Marketing | `5558bb48-a4ec-49ba-9e48-b9ca92f3461f` | 24h |
| Shopify | `c79a5968-f31b-44b9-b9e6-fa79e630fa40` | 24h |
| TikTok Marketing | `292df228-3e1b-4dc2-879e-bd78cc15bcf8` | 24h |

Trigger script: `vm_scripts/trigger_all_syncs.sh`
Monitoring: `data_validation/sync_watchdog.py` (hourly)
Reconciliation: `data_validation/reconciliation_check.py`
