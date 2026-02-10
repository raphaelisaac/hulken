# Analyst Quick Start Guide - A to Z

> This guide explains how to access the data, run queries, verify everything is working, and refresh syncs.
> Prerequisite: have a Google account with access to the GCP project `hulken`.

---

## Table of Contents

1. [Installation (one-time setup)](#1-installation-one-time-setup)
2. [Accessing BigQuery](#2-accessing-bigquery)
3. [Your first queries](#3-your-first-queries)
4. [Verifying data (Shopify vs BigQuery)](#4-verifying-data-shopify-vs-bigquery)
5. [Important tables](#5-important-tables)
6. [Running a report](#6-running-a-report)
7. [Refreshing data (syncs)](#7-refreshing-data-syncs)
8. [Verifying data integrity (Reconciliation)](#8-verifying-data-integrity-reconciliation)
9. [Exploring with the Streamlit dashboard](#9-exploring-with-the-streamlit-dashboard)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Installation (one-time setup)

### Option A: BigQuery web interface (nothing to install)

1. Go to https://console.cloud.google.com/bigquery
2. Log in with your Google account that has access to the `hulken` project
3. In the left menu, click `hulken` > `ads_data`
4. You can see all the tables. You're ready to go.

**This is the simplest method to get started.**

### Option B: VSCode + Python (for CSV exports and scripts)

**Windows:**
```
# 1. Install Google Cloud SDK
#    Download from: https://cloud.google.com/sdk/docs/install
#    Run the installer, check "Run gcloud init"

# 2. Authenticate (a browser window will open)
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken

# 3. Install Python packages
pip install google-cloud-bigquery pandas db-dtypes streamlit python-dotenv
```

**Mac:**
```bash
brew install --cask google-cloud-sdk
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken
pip3 install google-cloud-bigquery pandas db-dtypes streamlit python-dotenv
```

**Verify it works:**
```bash
python -c "from google.cloud import bigquery; c=bigquery.Client(project='hulken'); print('OK -', len(list(c.list_tables('ads_data'))), 'tables')"
```
You should see: `OK - 35 tables` (approximately)

---

## 2. Accessing BigQuery

### Via the web interface (recommended for beginners)

1. Open https://console.cloud.google.com/bigquery?project=hulken
2. In the left panel: `hulken` > `ads_data`
3. Click on a table to see its schema
4. "Preview" tab to see the data
5. "Query" button at the top to write SQL
6. Copy-paste a query from this guide, click "Run"

### Via Python (for exports and automation)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

# Run a query
sql = "SELECT COUNT(*) as total FROM `hulken.ads_data.shopify_live_orders_clean`"
result = client.query(sql).to_dataframe()
print(result)

# Export to CSV
sql = "SELECT * FROM `hulken.ads_data.shopify_live_orders_clean` LIMIT 1000"
df = client.query(sql).to_dataframe()
df.to_csv('export.csv', index=False)
print(f"Exported: {len(df)} rows")
```

---

## 3. Your first queries

Copy-paste these queries into BigQuery. They work out of the box.

### 3.1 How many orders per day?

```sql
SELECT
  DATE(created_at) AS date,
  COUNT(*) AS order_count,
  ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS total_revenue,
  ROUND(AVG(CAST(total_price AS FLOAT64)), 2) AS avg_order_value
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

**Expected results (as of Feb 9, 2026):**

| date | order_count | total_revenue | avg_order_value |
|------|-------------|-------------|--------------|
| 2026-02-09 | ~195 | ~30,479 | ~156 |
| 2026-02-08 | ~756 | ~117,414 | ~155 |
| 2026-02-07 | ~716 | ~110,387 | ~154 |
| 2026-02-06 | ~597 | ~89,355 | ~150 |

> If you see numbers close to these, your connection is working and the data is there.

### 3.2 Facebook spend per day

```sql
SELECT
  date_start AS date,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend_facebook,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clics
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

> Always use `facebook_insights` (not `facebook_ads_insights` which is the raw Airbyte table).

### 3.2b Facebook spend per campaign (like TikTok)

```sql
-- View facebook_campaigns_daily: equivalent of tiktokcampaigns_reports_daily
SELECT
  campaign_name,
  account_name,
  date_start AS date,
  spend,
  impressions,
  clicks,
  ad_count
FROM `hulken.ads_data.facebook_campaigns_daily`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
ORDER BY spend DESC
```

> **3 Facebook accounts** are available:
> - `Hulken` = **US** account (the largest, ~$8M total spend)
> - `Hulken Europe` = **EU** account (~$345K spend)
> - `Hulken Canada` = **CA** account (stopped in Dec 2024, ~$11K)
>
> To filter by region: `WHERE account_name = 'Hulken'` (US) or `WHERE account_name = 'Hulken Europe'`

### 3.3 TikTok spend per day

```sql
SELECT
  report_date AS date,
  ROUND(SUM(spend), 2) AS spend_tiktok,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clics
FROM `hulken.ads_data.tiktok_ads_reports_daily`
GROUP BY 1
ORDER BY 1 DESC
LIMIT 30
```

> `tiktok_ads_reports_daily` is a view that extracts metrics from the raw JSON. The `report_date` column is already formatted as DATE.

### 3.4 Revenue by acquisition source (UTM)

```sql
SELECT
  first_utm_source AS source,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue,
  ROUND(AVG(total_price), 2) AS avg_order_value
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND first_utm_source IS NOT NULL
GROUP BY 1
ORDER BY revenue DESC
```

### 3.5 Quick health check: is everything up to date?

```sql
SELECT
  table_id AS table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS last_updated,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS hours_behind,
  row_count AS row_count,
  ROUND(size_bytes / 1048576, 1) AS size_mb
FROM `hulken.ads_data.__TABLES__`
WHERE table_id IN (
  'facebook_ads_insights',
  'tiktokads_reports_daily',
  'shopify_live_orders',
  'shopify_live_orders_clean',
  'shopify_live_customers_clean',
  'shopify_utm'
)
ORDER BY hours_behind DESC
```

**What to check:**
- `shopify_live_orders`: < 30h delay = OK
- `facebook_ads_insights`: < 30h = OK, > 48h = PROBLEM
- `tiktokads_reports_daily`: < 30h = OK
- `shopify_utm`: < 24h = OK

> **More comprehensive alternative**: run `python data_validation/reconciliation_check.py --checks freshness,sync_lag` which checks everything automatically with diagnostics.

---

## 4. Verifying data (Shopify vs BigQuery)

Here is how to cross-reference what you see in Shopify Admin with what is in BigQuery.

### 4.1 Verify order count for a specific date

**In Shopify Admin:** Go to Orders, filter by date (e.g., February 5, 2026), note the total number.

**In BigQuery:**
```sql
-- Number of orders on February 5, 2026
SELECT COUNT(*) AS order_count,
  ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS revenue
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) = '2026-02-05'
```

**The number should be identical** (or very close, a few hours of delay is possible at end of day).

### 4.2 Verify a specific order

If you have the order number (e.g., #BS12345):

```sql
-- Search for an order by its name
SELECT id, name, CAST(total_price AS FLOAT64) AS price, created_at, currency
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE name = '#BS12345'
```

### 4.3 Verify Facebook spend vs Facebook Ads Manager

**In Facebook Ads Manager:** Note the total spend for a campaign over 7 days.

**In BigQuery:**
```sql
-- Spend per campaign (last 7 days)
SELECT
  campaign_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend,
  SUM(impressions) AS impressions
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1
ORDER BY spend DESC
```

> BigQuery numbers may be 1-2 days behind Facebook Ads Manager. This is normal because Airbyte syncs once per day.

### 4.4 Verify that PII is properly protected

```sql
-- Verify: no real emails, only SHA-256 hashes
SELECT
  email_hash,
  LENGTH(email_hash) AS hash_length
FROM `hulken.ads_data.shopify_live_orders_clean`
LIMIT 5
```

**You should see** 64-character hexadecimal strings, like:
`a3f2b8c4d5e6f7...` - never a plaintext email.

---

## 5. Important tables

### What you use daily:

| Table | Contents | Key columns |
|-------|----------|-------------|
| `shopify_live_orders_clean` | Recent orders (Airbyte) | id, name, total_price, created_at, email_hash, currency |
| `shopify_live_customers_clean` | Customers (Airbyte) | id, email_hash, total_spent, orders_count |
| `shopify_utm` | UTM attribution per order | order_id, total_price, first_utm_source, first_utm_campaign |
| `shopify_orders` | Full history (585K orders) | id, name, totalPrice, createdAt, email_hash |
| `facebook_insights` | Facebook performance (per ad/day) | campaign_name, date_start, spend, impressions, clicks, account_name |
| `facebook_campaigns_daily` | Facebook performance (per campaign/day) | campaign_name, date_start, spend, impressions, clicks, account_name |
| `tiktok_ads_reports_daily` | TikTok performance | campaign_id, report_date, spend, impressions, clicks |
| `tiktok_campaigns` | TikTok campaign names | campaign_id, campaign_name |

### Naming convention

All tables follow the format: `platform_entity`. Examples:
- `facebook_insights` - Facebook ad performance
- `tiktok_ads_reports_daily` - TikTok ad performance
- `tiktok_campaigns` - TikTok campaign catalog
- `shopify_live_orders_clean` - orders with protected PII

> Views are aliases (0 bytes of additional storage) that point to the Airbyte source tables.

### What you do NOT use directly:

| Raw Airbyte table | Why | Use instead |
|-------------------|-----|-------------|
| `facebook_ads_insights` | Contains duplicates (~20%) | `facebook_insights` (deduplicated) |
| `tiktokads_reports_daily` | Metrics in raw JSON | `tiktok_ads_reports_daily` (clean columns) |
| `shopify_live_orders` | Unprotected PII | `shopify_live_orders_clean` |
| `tiktokads`, `tiktokad_groups`, `tiktokcampaigns` | Airbyte names without underscores | `tiktok_ads`, `tiktok_ad_groups`, `tiktok_campaigns` |

### Golden rules:
1. **Facebook**: always use `facebook_insights` (or `facebook_insights_country`, `facebook_insights_age_gender`, etc.)
2. **TikTok performance**: always use `tiktok_ads_reports_daily` (metrics already extracted from JSON)
3. **TikTok metadata**: `tiktok_campaigns`, `tiktok_ads`, `tiktok_ad_groups` (clean names with underscores)
4. **Shopify PII**: always use `_clean` (never the tables without `_clean`)
5. **TikTok joins**: reports -> `tiktokads` (via ad_id) -> `tiktokcampaigns` (via campaign_id)

---

## 6. Running a report

### Facebook ROAS report (per campaign)

```sql
SELECT
  u.first_utm_campaign AS campaign,
  COUNT(DISTINCT u.order_id) AS orders,
  ROUND(SUM(u.total_price), 2) AS revenue,
  f.spend,
  ROUND(SUM(u.total_price) / NULLIF(f.spend, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT campaign_name, ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend
  FROM `hulken.ads_data.facebook_insights`
  GROUP BY 1
) f ON u.first_utm_campaign = f.campaign_name
WHERE u.first_utm_source LIKE '%facebook%'
GROUP BY 1, f.spend
ORDER BY revenue DESC
```

### TikTok ROAS report (per campaign)

```sql
SELECT
  u.first_utm_campaign AS campaign,
  COUNT(DISTINCT u.order_id) AS orders,
  ROUND(SUM(u.total_price), 2) AS revenue,
  t.spend,
  ROUND(SUM(u.total_price) / NULLIF(t.spend, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  -- Join: reports -> ads -> campaigns (campaign_id is not in reports)
  SELECT c.campaign_name,
    ROUND(SUM(CAST(JSON_EXTRACT_SCALAR(r.metrics, '$.spend') AS FLOAT64)), 2) AS spend
  FROM `hulken.ads_data.tiktokads_reports_daily` r
  JOIN `hulken.ads_data.tiktokads` a ON r.ad_id = a.ad_id
  JOIN `hulken.ads_data.tiktokcampaigns` c ON a.campaign_id = c.campaign_id
  GROUP BY 1
) t ON u.first_utm_campaign = t.campaign_name
WHERE u.first_utm_source LIKE '%tiktok%'
GROUP BY 1, t.spend
ORDER BY revenue DESC
```

> **Note**: For TikTok, the `tiktokads_reports_daily` table only contains `ad_id`. You need to join via `tiktokads` (ad -> campaign) then `tiktokcampaigns` (campaign -> name).

### CAC report (customer acquisition cost per channel)

```sql
SELECT
  first_utm_source AS canal,
  COUNT(DISTINCT order_id) AS nouveaux_clients,
  ROUND(SUM(total_price), 2) AS first_order_revenue,
  ROUND(AVG(total_price), 2) AS avg_order_value,
  ROUND(AVG(days_to_conversion), 1) AS jours_moy_conversion
FROM `hulken.ads_data.shopify_utm`
WHERE customer_order_index = 1  -- first order only
GROUP BY 1
ORDER BY nouveaux_clients DESC
```

### Daily cross-platform report

```sql
WITH daily_fb AS (
  SELECT DATE(date_start) AS dt,
    ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS fb_spend
  FROM `hulken.ads_data.facebook_insights`
  GROUP BY 1
),
daily_tt AS (
  SELECT report_date AS dt,
    ROUND(SUM(spend), 2) AS tt_spend
  FROM `hulken.ads_data.tiktok_ads_reports_daily`
  GROUP BY 1
),
daily_rev AS (
  SELECT DATE(created_at) AS dt,
    ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS revenue,
    COUNT(*) AS orders
  FROM `hulken.ads_data.shopify_utm`
  GROUP BY 1
)
SELECT
  r.dt AS date,
  r.orders,
  r.revenue,
  COALESCE(f.fb_spend, 0) AS spend_facebook,
  COALESCE(t.tt_spend, 0) AS spend_tiktok,
  COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0) AS total_spend,
  ROUND(r.revenue / NULLIF(COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0), 0), 2) AS blended_roas
FROM daily_rev r
LEFT JOIN daily_fb f ON r.dt = f.dt
LEFT JOIN daily_tt t ON r.dt = t.dt
WHERE r.dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY r.dt DESC
```

### Export a report to CSV (Python)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

sql = """
SELECT DATE(created_at) AS date,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1 ORDER BY 1
"""

df = client.query(sql).to_dataframe()
df.to_csv('revenue_report_30d.csv', index=False)
print(f"Exported {len(df)} days to revenue_report_30d.csv")
```

---

## 7. Refreshing data (syncs)

### When to refresh?

Syncs run automatically every 24 hours via Airbyte. You normally don't need to do anything.
Run the health check (query 3.5 above) to check for delays.

### If a sync is delayed (> 48h)

**Method 1: Via the Airbyte UI (simplest)**

```bash
# Terminal 1: open the SSH tunnel to the Airbyte VM
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap -- -L 8000:localhost:8000
```

Then open http://localhost:8000 in your browser.
- Login: `admin` / `gTafVpBcdHhBh56G`
- You'll see the 3 connections: Facebook, Shopify, TikTok
- Click on the delayed one > "Sync now"

**Method 2: Via script (if the UI doesn't work)**

```bash
# Copy the script to the VM and execute it
gcloud compute scp vm_scripts/trigger_all_syncs.sh Jarvis@instance-20260129-133637:/tmp/ --zone=us-central1-a --tunnel-through-iap
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --command='bash /tmp/trigger_all_syncs.sh'
```

You should see:
```
=== Getting auth token ===
Token: OK
=== Triggering syncs ===
  Facebook Marketing: job=XXX status=running
  Shopify: job=XXX status=running
  TikTok Marketing: job=XXX status=running
=== All syncs triggered ===
```

### How long does it take?

| Source | Typical duration | Backfill after delay |
|--------|-----------------|----------------------|
| Facebook | 15-30 min | +5 min per day of delay |
| Shopify | 5-10 min | +2 min per day |
| TikTok | 5-15 min | +3 min per day |

### The UTM script (shopify_utm) syncs separately

It runs on the VM via cron every hour:
```bash
# To verify it's running:
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --command='crontab -l'
```

---

## 8. Verifying data integrity (Reconciliation)

Two reconciliation scripts allow you to verify that all data is present, fresh, and consistent.

### 8.1 Full reconciliation (10 checks, 56 tests)

```bash
cd D:\Better_signal     # Windows
cd ~/Better_signal      # Mac

# Run all checks
python data_validation/reconciliation_check.py

# Run only specific checks
python data_validation/reconciliation_check.py --checks freshness,duplicates
python data_validation/reconciliation_check.py --checks facebook_daily,ga4

# Specify a date range
python data_validation/reconciliation_check.py --start 2026-01-01 --end 2026-01-31
```

**What it checks (10 categories):**

| Check | What it does |
|-------|-------------|
| `freshness` | Latest date for each source (Facebook, TikTok, Shopify, UTM) |
| `duplicates` | Duplicates in each table (`_clean` tables should be at 0%) |
| `pii` | Zero email/phone/name in plaintext in raw tables |
| `hashes` | All SHA256 hashes are 64 characters, cross-table match > 70% |
| `continuity` | No missing days in the last 30 days |
| `nulls` | Critical fields (spend, date, ad_id) are never NULL |
| `pii_schedule` | The PII scheduled query runs every 5 minutes |
| `facebook_daily` | Facebook daily spend (deduplicated) |
| `ga4` | Freshness of the 3 GA4 properties (EU, US, CA) |
| `sync_lag` | Hours since the last update of each table |

**Expected result:** 56/56 PASS (duplicates in raw Shopify tables show as WARNING, not FAIL — the `_clean` tables are clean).

**Output:** `data_validation/reconciliation_results.json` (full JSON report)

### 8.2 Visual HTML report

```bash
python data_validation/reconciliation_report.py
```

This generates an HTML report at `data_validation/reconciliation_report.html` and opens it in the browser. The report shows:
- Facebook: records, spend per account, missing accounts
- TikTok: records, total spend, date range
- Shopify: orders, revenue, unique customers
- UTM: attribution rate
- Freshness of each source

### 8.3 Manual verification (spot check)

To verify that a number in BigQuery matches the source:

```sql
-- Example: Facebook spend on February 8
SELECT ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend
FROM `hulken.ads_data.facebook_insights`
WHERE date_start = '2026-02-08'
-- Expected result: ~$21,491 (compare with Facebook Ads Manager)

-- Example: TikTok spend on February 8
SELECT ROUND(SUM(spend), 2) AS spend
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE report_date = '2026-02-08'
-- Compare with TikTok Ads Manager
```

---

## 9. Exploring with the Streamlit dashboard

A Streamlit dashboard exists to visually explore all tables, write queries, and export to CSV.

### Launch the dashboard

```bash
cd D:\Better_signal     # Windows
cd ~/Better_signal      # Mac

streamlit run data_explorer.py
```

This opens a browser (http://localhost:8501) with 4 tabs:
- **Schema**: all columns of a table with types and size
- **Preview**: view the first 100 rows of any table
- **Query + Export**: write free-form SQL, view results, download as CSV
- **Overview**: all tables in the dataset with row count, size, last update

### Available datasets

| Dataset | Contents |
|---------|----------|
| `ads_data` | Shopify, Facebook, TikTok, UTM (main dataset) |
| `google_Ads` | Google Ads (190 tables, native integration) |
| `analytics_334792038` | Google Analytics 4 - Europe |
| `analytics_454869667` | Google Analytics 4 - USA |
| `analytics_454871405` | Google Analytics 4 - Canada |

### Built-in quick queries

The dashboard includes pre-built queries (Query + Export tab > Quick Queries):
- Daily revenue (30 days)
- Facebook spend per campaign
- TikTok daily spend
- UTM attribution per source
- Data freshness check
- Google Ads daily spend

### Export to CSV

1. Run a query in the "Query + Export" tab
2. Click "Download CSV" under the results
3. The file is downloaded directly

---

## 10. Troubleshooting

### "I can't connect to BigQuery"

```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken

# Test
bq ls hulken:ads_data
```

If it still doesn't work: your Google account doesn't have permissions on the `hulken` project. Ask the GCP admin for access.

### "The query returns 0 results"

1. Check the table name (use `tiktok_ads_reports_daily` not `tiktokads_reports_daily`)
2. Check the date range - data does not go back more than ~6 months
3. Run the health check (query 3.5) to see if the table has data

### "The numbers don't match Shopify"

- Normal delay: up to 24h between Shopify and BigQuery
- The `shopify_live_*` tables are synced by Airbyte (24h)
- The `shopify_utm` table is synced separately (hourly)
- Test orders (`test = true`) are included - filter with `WHERE test = false` if needed

### "Facebook shows X spend but BigQuery shows Y"

1. Check that you are using `facebook_insights` (not `facebook_ads_insights` directly)
2. Facebook Ads Manager is real-time, BigQuery has a 24h delay
3. Facebook's attribution window can cause numbers to vary

### Useful scripts

| What | Command |
|------|---------|
| Full reconciliation (56 tests) | `python data_validation/reconciliation_check.py` |
| Live reconciliation (API vs BigQuery) | `python data_validation/live_reconciliation.py` |
| Visual HTML report | `python data_validation/reconciliation_report.py` |
| Streamlit dashboard | `streamlit run data_explorer.py` |
| Quick reconciliation (2 checks) | `python data_validation/reconciliation_check.py --checks freshness,duplicates` |
| Restart all syncs | See section 7 |

---

## Aide-memoire

```
GCP Project       : hulken
Main Dataset      : ads_data
Google Ads Dataset: google_Ads

-- SHOPIFY --
Orders            : shopify_live_orders_clean  (or shopify_orders for historical)
Customers         : shopify_live_customers_clean
Attribution       : shopify_utm

-- FACEBOOK (3 accounts) --
Hulken (US)       : account_id 440461496366294  ($8M spend, since Feb 2024)
Hulken Europe     : account_id 1673934429844193 ($345K spend, since Oct 2024)
Hulken Canada     : account_id 1686648438857084 ($11K spend, stopped Dec 2024)
Facebook metrics  : facebook_insights
Facebook campaigns: facebook_campaigns_daily (aggregated view by campaign/day)
Facebook demo     : facebook_insights_age_gender, facebook_insights_country, facebook_insights_region

-- TIKTOK --
TikTok metrics    : tiktok_ads_reports_daily
TikTok campaigns  : tiktokcampaigns

-- GOOGLE ADS --
Google Ads stats  : google_Ads.ads_CampaignBasicStats_4354001000 (metrics_cost_micros / 1e6 = USD)

-- TOOLS --
Airbyte VM        : instance-20260129-133637 (zone us-central1-a)
Reconciliation    : python data_validation/reconciliation_check.py
Live recon (demo) : python data_validation/live_reconciliation.py
Dashboard         : streamlit run data_explorer.py
```
