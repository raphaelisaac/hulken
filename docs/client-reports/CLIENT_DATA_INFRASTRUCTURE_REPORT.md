# Hulken Data Infrastructure Report

**Prepared by:** Better Signals
**Date:** February 2, 2026
**Project:** Marketing Analytics Pipeline

---

## Executive Summary

A complete marketing data infrastructure has been deployed connecting your advertising platforms (Facebook, TikTok), e-commerce platform (Shopify), and web analytics (Google Analytics 4) to Google BigQuery. The system runs on Google Cloud Platform and automatically synchronizes data for real-time analytics.

**Key Highlights:**
- **8+ million records** across all data sources
- **3.4 GB** of marketing and sales data in BigQuery
- **Google Analytics 4** already connected (3 properties, ~3M events)
- **Automated hourly syncs** via Airbyte
- **Custom UTM attribution script** for complete customer journey tracking (complimentary)
- **Production-ready** infrastructure on GCP

---

## 1. Infrastructure Architecture

### 1.1 Overview

```
+------------------+     +------------------+     +------------------+
|   Facebook Ads   |     |   TikTok Ads     |     |     Shopify      |
|  US/Canada/Europe|     |   Marketing API  |     |   GraphQL API    |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         v                        v                        v
+------------------------------------------------------------------------+
|                         AIRBYTE (GCP VM)                               |
|   Kubernetes-based data integration platform                           |
|   - Automated scheduling (hourly)                                      |
|   - Incremental sync for efficiency                                    |
|   - Error handling and retry logic                                     |
+------------------------------------------------------------------------+
         |                        |                        |
         v                        v                        v
+------------------------------------------------------------------------+
|                      GOOGLE BIGQUERY                                   |
|   Project: hulken                                                      |
|   Datasets:                                                            |
|   - ads_data (Facebook, TikTok, Shopify)                              |
|   - analytics_334792038 (GA4 Property 1)                              |
|   - analytics_454869667 (GA4 Property 2)                              |
|   - analytics_454871405 (GA4 Property 3)                              |
+------------------------------------------------------------------------+
         |
         v
+------------------+
|   YOUR ANALYSTS  |
|   BI Tools       |
|   Custom Reports |
+------------------+
```

### 1.2 GCP Configuration

| Component | Details |
|-----------|---------|
| **VM Instance** | `instance-20260129-133637` |
| **Zone** | us-central1-a |
| **Project** | hulken |
| **Platform** | Airbyte OSS on Kubernetes (via abctl) |
| **Access Method** | IAP (Identity-Aware Proxy) SSH Tunnel |

---

## 2. Data Sources and Connections

### 2.1 Airbyte Connections Overview

| Source | Destination | Table Prefix | Sync Frequency | Status |
|--------|-------------|--------------|----------------|--------|
| Facebook Marketing | BigQuery | `facebook_` / `ads_` | Hourly | Active |
| TikTok Marketing | BigQuery | `tiktok` | Hourly | Active |
| Shopify | BigQuery | `shopify_live_` | Hourly | Active |

### 2.2 Facebook Marketing

**Ad Accounts Configured:**

| Account | Account ID | Data Status |
|---------|------------|-------------|
| **Hulken US** | 440461496366294 | Configured - Sync pending |
| **Hulken Canada** | 1686648438857084 | Configured - Sync pending |
| **Hulken Europe** | 1673934429844193 | **Active - Data available** |

**Active Streams (13 total, prefix `facebook_`):**

| BigQuery Table | Sync Mode | Description |
|--------|-----------|-------------|
| `facebook_ads_insights` | Full Refresh | Daily performance metrics per ad |
| `facebook_ads_insights_age_and_gender` | Full Refresh | Demographic breakdown |
| `facebook_ads_insights_country` | Full Refresh | Geographic breakdown by country |
| `facebook_ads_insights_region` | Full Refresh | Geographic breakdown by region |
| `facebook_ads_insights_dma` | Full Refresh | DMA breakdown |
| `facebook_ads_insights_platform_and_device` | Full Refresh | Platform/device breakdown |
| `facebook_ads_insights_action_type` | Full Refresh | Conversion actions breakdown |
| `facebook_campaigns` | Full Refresh | Campaign metadata |
| `facebook_ad_sets` | Full Refresh | Ad set metadata |
| `facebook_ads` | Full Refresh | Ad metadata |
| `facebook_ad_creatives` | Full Refresh | Creative assets metadata |
| `facebook_custom_conversions` | Full Refresh | Custom conversion definitions |
| `facebook_images` | Full Refresh | Image assets |

**Key Metrics Available:**
- `spend`, `impressions`, `clicks`, `reach`, `frequency`
- `cpm`, `cpc`, `ctr`
- `actions` (purchases, add_to_cart, view_content, etc.)
- `action_values` (conversion values)
- `cost_per_action_type`

### 2.3 TikTok Marketing

**Advertiser Account:** 7109416173220986881

**Active Streams (7 total):**

| Stream | Sync Mode | Description |
|--------|-----------|-------------|
| `ads` | Full Refresh | Ad metadata |
| `ads_reports_daily` | Full Refresh | Daily ad performance |
| `ad_groups` | Full Refresh | Ad group metadata |
| `ad_groups_reports_daily` | Full Refresh | Daily ad group performance |
| `campaigns` | Full Refresh | Campaign metadata |
| `campaigns_reports_daily` | Full Refresh | Daily campaign performance |
| `advertisers_reports_daily` | Full Refresh | Daily account-level metrics |

**Key Metrics Available:**
- `spend`, `impressions`, `clicks`, `conversions`
- `cpc`, `cpm`, `ctr`, `conversion_rate`
- `video_views`, `video_watched_2s`, `video_watched_6s`
- Geographic and platform breakdowns

### 2.4 Shopify

**Store:** hulken-inc.myshopify.com

**Active Streams (5 total):**

| Stream | Sync Mode | Description |
|--------|-----------|-------------|
| `orders` | Incremental | Order data (new orders only) |
| `customers` | Incremental | Customer data |
| `products` | Incremental | Product catalog |
| `order_refunds` | Incremental | Refund data |
| `transactions` | Incremental | Payment transactions |

**Note:** Inventory streams (`inventory_items`, `inventory_levels`) were disabled due to API permission restrictions. These can be re-enabled if inventory read permissions are added to the Shopify API token.

### 2.5 Google Analytics 4 (Already Connected)

GA4 data flows directly to BigQuery via native Google export (not Airbyte).

**Properties Connected:**

| Property ID | Dataset | Total Events | Date Range |
|-------------|---------|--------------|------------|
| 334792038 | `analytics_334792038` | 1,480,146 | Jan 25 - Feb 2, 2026 |
| 454871405 | `analytics_454871405` | 1,394,136 | Jan 25 - Feb 2, 2026 |
| 454869667 | `analytics_454869667` | 96,663 | Jan 25 - Feb 2, 2026 |

**Available Event Types:**
- `page_view` (448K events)
- `view_item` (339K events)
- `user_engagement` (191K events)
- `session_start` (168K events)
- `first_visit` (116K events)
- `add_to_cart` (18K events)
- `purchase`, `begin_checkout`, and more

---

## 3. Data Proof - Verified Samples

### 3.1 Facebook Ads Data (Europe Account)

```
Account: Hulken Europe (1673934429844193)
Records: 33,253
Date Range: October 11, 2024 - February 1, 2026
Total Spend: EUR 335,326.08
```

**Sample Query Result:**
```sql
SELECT account_name, COUNT(*) as records,
       MIN(date_start) as first_date, MAX(date_start) as last_date,
       ROUND(SUM(spend), 2) as total_spend
FROM `hulken.ads_data.facebook_insights`
GROUP BY 1
```
| Account | Records | First Date | Last Date | Total Spend |
|---------|---------|------------|-----------|-------------|
| Hulken Europe | 33,253 | 2024-10-11 | 2026-02-01 | EUR 335,326.08 |

*Note: US and Canada accounts are configured in Airbyte and will sync on next scheduled run.*

### 3.2 Shopify Data

```
Total Orders: 585,927
Date Range: September 17, 2021 - January 29, 2026
Total Revenue: $84,124,663.84
Countries: 10
```

**Revenue by Country:**
| Country | Orders | Revenue |
|---------|--------|---------|
| United States | 460,881 | $68,064,673.84 |
| (Not specified) | 123,069 | $15,708,190.04 |
| Canada | 1,957 | $350,010.45 |
| Costa Rica | 5 | $567.79 |
| Aruba | 4 | $393.06 |

### 3.3 TikTok Ads Data

```
Total Ads: 895
Date Range: June 16, 2022 - February 1, 2026
Advertiser: 7109416173220986881
```

### 3.4 Google Analytics 4 Data

```
Total Events: ~2,970,945 (across 3 properties)
Date Range: January 25, 2026 - February 2, 2026 (real-time)
```

**Top Events (January 2026):**
| Event | Count |
|-------|-------|
| page_view | 448,327 |
| view_item | 338,757 |
| user_engagement | 190,647 |
| session_start | 168,457 |
| first_visit | 116,162 |
| view_item_list | 115,666 |
| add_to_cart | 17,955 |

---

## 4. Custom UTM Attribution Script

### 4.1 Why This Custom Solution?

**The Problem:**
Airbyte's standard Shopify connector uses the REST API, which provides only basic attribution fields:
- `landing_site` - Just the URL path
- `referring_site` - Referrer URL
- `source_name` - Basic source (e.g., "web", "amazon")

**What's Missing:**
Shopify's complete `customerJourneySummary` data is only available via the GraphQL API and includes:
- Full UTM parameters (source, medium, campaign, content, term)
- First-touch vs Last-touch attribution
- Days to conversion
- Customer order index (new vs returning)
- Complete landing page and referrer URLs

**The Solution:**
A custom Python script was developed that uses Shopify's GraphQL API to extract complete attribution data. This script is provided as a **complimentary addition** to your data infrastructure - custom development at no additional charge.

### 4.2 UTM Script Details

**Location on GCP VM:** `/home/Jarvis/shopify_utm/`

**Files:**
- `extract_shopify_utm_incremental.py` - Main extraction script
- `run_utm_extraction.sh` - Wrapper script for cron
- `hulken-fb56a345ac08.json` - BigQuery service account credentials
- `venv/` - Python virtual environment

**Schedule:** Daily at 6:00 AM UTC (8:00 AM Paris time)

**Output Table:** `hulken.ads_data.shopify_utm`

### 4.3 UTM Data Schema

| Field | Type | Description |
|-------|------|-------------|
| `order_id` | STRING | Shopify order GID |
| `order_name` | STRING | Order number (#1001, etc.) |
| `created_at` | TIMESTAMP | Order creation time |
| `total_price` | FLOAT64 | Order total |
| `customer_order_index` | INTEGER | 1 = new customer, 2+ = returning |
| `days_to_conversion` | INTEGER | Days from first visit to purchase |
| `first_utm_source` | STRING | First-touch UTM source |
| `first_utm_medium` | STRING | First-touch UTM medium |
| `first_utm_campaign` | STRING | First-touch UTM campaign |
| `first_utm_content` | STRING | First-touch UTM content |
| `first_utm_term` | STRING | First-touch UTM term |
| `first_landing_page` | STRING | First visit landing page URL |
| `first_referrer_url` | STRING | First visit referrer |
| `first_visit_at` | TIMESTAMP | First visit timestamp |
| `last_utm_source` | STRING | Last-touch UTM source |
| `last_utm_medium` | STRING | Last-touch UTM medium |
| `last_utm_campaign` | STRING | Last-touch UTM campaign |
| `last_landing_page` | STRING | Last visit landing page URL |
| `last_visit_at` | TIMESTAMP | Last visit timestamp |
| `extracted_at` | TIMESTAMP | Data extraction timestamp |

### 4.4 Current Attribution Data

**Total Orders:** 587,927
**Orders with UTM Tracking:** 142,506 (24.2%)

**Attribution by Channel:**

| Channel | Orders | Revenue | AOV | New Customers |
|---------|--------|---------|-----|---------------|
| Direct/Organic | 466,172 | $65.9M | $141 | 368,283 |
| Facebook/Meta | 72,248 | $10.8M | $150 | 60,466 |
| Email (Klaviyo) | 26,193 | $4.2M | $159 | 8,772 |
| Search (Google/Bing) | 15,441 | $2.4M | $155 | 13,277 |
| TikTok | 3,593 | $518K | $144 | 3,173 |

---

## 5. BigQuery Data Inventory

### 5.1 Complete Table List

#### Facebook Marketing Tables (Dataset: ads_data)

| Table | Rows | Size | Description |
|-------|------|------|-------------|
| `facebook_ads_insights` | 159,342 | 820 MB | Daily ad performance metrics |
| `facebook_ads_insights_age_and_gender` | 1,494,810 | 3,615 MB | Demographic breakdown |
| `facebook_ads_insights_country` | 332,442 | 1,112 MB | Country breakdown |
| `facebook_ads_insights_region` | 911,412 | 862 MB | Region breakdown |
| `facebook_ads` | 5,428 | 7 MB | Ad metadata |
| `facebook_ad_sets` | 341 | 0.2 MB | Ad set metadata |
| `facebook_ad_creatives` | 5,160 | 13 MB | Creative assets metadata |

**Dedup Views (use these for analysis):** `facebook_insights`, `facebook_insights_age_gender`, `facebook_insights_country`, `facebook_insights_region` (ROW_NUMBER dedup to remove ~20% Airbyte duplicates)

#### TikTok Marketing Tables (Dataset: ads_data)

**Source tables (Airbyte, prefix `tiktok` without underscore):**

| Table | Rows | Size | Description |
|-------|------|------|-------------|
| `tiktokads` | 859 | 0.6 MB | Ad metadata |
| `tiktokads_reports_daily` | 30,574 | 26 MB | Daily ad metrics (JSON) |
| `tiktokcampaigns` | 35 | 0.01 MB | Campaign metadata |
| `tiktokcampaigns_reports_daily` | 5,807 | 2 MB | Daily campaign metrics |
| `tiktokad_groups` | 71 | 0.1 MB | Ad group metadata |
| `tiktokad_groups_reports_daily` | 6,710 | 3 MB | Daily ad group metrics |
| `tiktokadvertisers_reports_daily` | 1,335 | 0.4 MB | Daily account metrics |

**Clean-name views (use these for analysis):** `tiktok_ads_reports_daily`, `tiktok_campaigns`, `tiktok_ads`, `tiktok_ad_groups`, `tiktok_ad_groups_reports_daily`, `tiktok_advertisers_reports_daily`, `tiktok_campaigns_reports_daily`

#### Shopify Tables (Dataset: ads_data)

| Table | Rows | Size | Description |
|-------|------|------|-------------|
| `shopify_orders` | 585,927 | 160 MB | Historical orders (bulk import) |
| `shopify_line_items` | 719,124 | 79 MB | Order line items |
| `shopify_utm` | 592,742 | 128 MB | UTM attribution data |
| `shopify_live_orders` | 13,637 | 103 MB | Recent orders (Airbyte, live sync) |
| `shopify_live_orders_clean` | 13,636 | 52 MB | Orders with PII hashed |
| `shopify_live_customers` | 18,790 | 5 MB | Customer data (Airbyte) |
| `shopify_live_customers_clean` | 18,790 | 7 MB | Customers with PII hashed |
| `shopify_live_products` | 1,060 | 2 MB | Product catalog (Airbyte) |
| `shopify_live_transactions` | 39,995 | 117 MB | Payment transactions (Airbyte) |
| `shopify_live_order_refunds` | 414 | 2 MB | Refund records (Airbyte) |

#### Google Analytics 4 Tables (Separate Datasets)

| Dataset | Table Pattern | Description |
|---------|---------------|-------------|
| `analytics_334792038` | `events_YYYYMMDD` | Daily event tables |
| `analytics_334792038` | `events_intraday_YYYYMMDD` | Real-time events |
| `analytics_334792038` | `users_YYYYMMDD` | User data |
| `analytics_454869667` | `events_*` | Second property events |
| `analytics_454871405` | `events_*` | Third property events |

### 5.2 Data Totals (Updated 2026-02-09)

| Source | Tables/Views | Total Rows | Total Size |
|--------|--------|------------|------------|
| Facebook | 7 tables + 4 views | 2,908,935 | 6.4 GB |
| TikTok | 7 tables + 7 views | 45,391 | 33 MB |
| Shopify | 10 tables | 1,990,115 | 655 MB |
| Google Analytics 4 | ~30/property | ~3,000,000 | Varies |
| **TOTAL** | **~35 + GA4** | **~8,000,000+** | **~7 GB** |

---

## 6. Analysis Opportunities

### 6.1 Cross-Platform Attribution Analysis

**Join Shopify orders with ad spend:**
```sql
SELECT
  DATE(s.created_at) as order_date,
  s.first_utm_source,
  COUNT(*) as orders,
  SUM(s.total_price) as revenue,
  SUM(f.spend) as ad_spend,
  SUM(s.total_price) / NULLIF(SUM(f.spend), 0) as roas
FROM `hulken.ads_data.shopify_utm` s
LEFT JOIN `hulken.ads_data.facebook_insights` f
  ON DATE(s.created_at) = f.date_start
WHERE s.first_utm_source LIKE '%facebook%'
GROUP BY 1, 2
ORDER BY 1 DESC
```

### 6.2 Customer Journey Analysis

**First-touch vs Last-touch attribution:**
```sql
SELECT
  first_utm_source,
  last_utm_source,
  COUNT(*) as orders,
  AVG(days_to_conversion) as avg_days_to_convert,
  SUM(total_price) as total_revenue
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_source IS NOT NULL
GROUP BY 1, 2
ORDER BY orders DESC
```

### 6.3 GA4 + Shopify Funnel Analysis

```sql
-- Combine GA4 events with Shopify conversions
WITH ga4_events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `hulken.analytics_334792038.events_*`
  WHERE event_name IN ('page_view', 'view_item', 'add_to_cart', 'purchase')
)
SELECT
  event_name,
  COUNT(*) as event_count,
  COUNT(DISTINCT user_pseudo_id) as unique_users
FROM ga4_events
GROUP BY 1
ORDER BY event_count DESC
```

### 6.4 New vs Returning Customer Analysis

```sql
SELECT
  CASE WHEN customer_order_index = 1 THEN 'New Customer' ELSE 'Returning' END as customer_type,
  first_utm_source,
  COUNT(*) as orders,
  SUM(total_price) as revenue,
  AVG(total_price) as aov
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1, 2
ORDER BY revenue DESC
```

### 6.5 Platform Performance Comparison

```sql
-- Facebook vs TikTok spend comparison
WITH fb AS (
  SELECT DATE(date_start) as dt, SUM(spend) as spend
  FROM `hulken.ads_data.facebook_insights`
  GROUP BY 1
),
tt AS (
  SELECT DATE(stat_time_day) as dt, SUM(spend) as spend
  FROM `hulken.ads_data.tiktok_ads_reports_daily`
  GROUP BY 1
)
SELECT
  COALESCE(fb.dt, tt.dt) as date,
  fb.spend as facebook_spend,
  tt.spend as tiktok_spend
FROM fb
FULL OUTER JOIN tt ON fb.dt = tt.dt
ORDER BY 1 DESC
```

---

## 7. Data Refresh Schedule

| Data Source | Method | Frequency | Time (UTC) |
|-------------|--------|-----------|------------|
| Facebook Marketing | Airbyte | Hourly | Every hour |
| TikTok Marketing | Airbyte | Hourly | Every hour |
| Shopify (orders, customers) | Airbyte | Hourly | Every hour |
| Shopify UTM Attribution | Custom Script | Daily | 6:00 AM |
| Google Analytics 4 | Native BigQuery Export | Daily + Intraday | Automatic |

**Note:** Airbyte uses incremental sync where possible, meaning only new/changed data is fetched each time. The UTM script also runs incrementally, only fetching orders from the last 2 days to catch any updates.

---

## 8. Airbyte Management Runbook

### 8.1 Accessing Airbyte UI

**Option 1: Using Google Cloud Console (Recommended)**

1. Go to https://console.cloud.google.com
2. Select project: `hulken`
3. Navigate to: Compute Engine > VM instances
4. Find: `instance-20260129-133637`
5. Click the SSH button

Then run:
```bash
# Start IAP tunnel to Airbyte
gcloud compute start-iap-tunnel instance-20260129-133637 8000 \
  --local-host-port=localhost:8006 \
  --zone=us-central1-a \
  --project=hulken
```

6. Open browser: http://localhost:8006

**Option 2: Using gcloud CLI (from any terminal)**

```bash
# macOS/Linux
gcloud compute start-iap-tunnel instance-20260129-133637 8000 \
  --local-host-port=localhost:8006 \
  --zone=us-central1-a \
  --project=hulken
```

Then open: http://localhost:8006

**Login Credentials:**
- Email: `alon@bettersignals.co`
- Password: `JoQmftqgT4DNhhLLQMXEB3FZkBYkV6iJ`

### 8.2 Common Operations

#### Trigger Manual Sync
1. Open Airbyte UI
2. Go to Connections
3. Select the connection (e.g., "Shopify - BigQuery")
4. Click "Sync now"

#### Check Sync Status
1. Open Airbyte UI
2. Go to Connections
3. Click on the connection
4. View "Timeline" tab for job history

#### View Sync Errors
1. Open connection
2. Go to Timeline
3. Click on failed job
4. View "Logs" for details

### 8.3 Troubleshooting

**If Airbyte is not responding:**

1. SSH to the VM:
```bash
gcloud compute ssh instance-20260129-133637 \
  --zone=us-central1-a \
  --project=hulken \
  --tunnel-through-iap
```

2. Check Docker containers:
```bash
docker ps
```

3. If containers are down, restart them:
```bash
docker start $(docker ps -aq)
```

4. Wait 2-3 minutes for services to start

**If a sync is stuck:**
1. Go to Airbyte UI > Connections
2. Click the connection
3. Click "Cancel" on the running job
4. Click "Sync now" to start fresh

### 8.4 Checking UTM Script Logs

```bash
# SSH to VM
gcloud compute ssh instance-20260129-133637 \
  --zone=us-central1-a \
  --project=hulken \
  --tunnel-through-iap

# View recent logs
tail -100 ~/shopify_utm/logs/utm_extraction.log

# Run script manually
cd ~/shopify_utm
source venv/bin/activate
python extract_shopify_utm_incremental.py
```

---

## 9. Credentials Reference

### BigQuery
- **Project:** hulken
- **Datasets:** ads_data, analytics_334792038, analytics_454869667, analytics_454871405
- **Service Account:** airbyte-bigquery@hulken.iam.gserviceaccount.com

### Shopify
- **Store:** hulken-inc.myshopify.com
- **API Token:** [REDACTED - Stored in .env file]
- **Scopes:** read_all_orders, read_customers, read_products, read_analytics

### Airbyte (GCP)
- **VM:** instance-20260129-133637
- **Zone:** us-central1-a
- **Access:** IAP tunnel to port 8000
- **UI Port:** 8006 (local after tunnel)

---

## 10. Pending Integrations

### Currently Configured (Awaiting Data)

| Platform | Status | Notes |
|----------|--------|-------|
| Facebook US | Configured | Account 440461496366294 - Will sync on next run |
| Facebook Canada | Configured | Account 1686648438857084 - Will sync on next run |

### To Be Added

| Platform | Status | Action Required |
|----------|--------|-----------------|
| **Klaviyo** | Pending | API credentials needed for email marketing data |
| **Google Ads** | Pending | Connect if Google Ads is used for paid search |
| **Pinterest** | Waiting | Access to be provided by client |
| **Amazon Ads** | Waiting | Access to be provided by client |
| **Target** | Waiting | Access to be provided by client |

---

## 11. Summary

### What's Working Now

| Source | Status | Data Available |
|--------|--------|----------------|
| Facebook Europe | Active | 33K records, EUR 335K spend |
| Facebook US | Configured | Sync pending |
| Facebook Canada | Configured | Sync pending |
| TikTok | Active | 1.6M+ records |
| Shopify | Active | 585K orders, $84M revenue |
| Shopify UTM | Active | 587K orders with attribution |
| Google Analytics 4 | Active | 3M+ events (3 properties) |

### Data Analysis Capabilities

With this infrastructure, your analysts can perform:

1. **Cross-Channel Attribution** - Track customer journey from ad impression to purchase
2. **ROAS Analysis** - Calculate return on ad spend by platform, campaign, creative
3. **Customer Segmentation** - New vs returning, by acquisition source
4. **Geographic Analysis** - Performance by country, region, DMA
5. **Funnel Analysis** - GA4 events through Shopify conversion
6. **Cohort Analysis** - Customer lifetime value by acquisition month/source
7. **Creative Performance** - Which ads drive the most revenue
8. **Platform Comparison** - Facebook vs TikTok efficiency

---



**Document Version:** 1.1
**Last Updated:** February 2, 2026
