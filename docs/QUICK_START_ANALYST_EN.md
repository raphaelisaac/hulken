# Analyst Quick Start Guide

> Everything you need to access and verify Hulken's advertising data.
> You need: a Google account with access to the project **hulken**.

---

## 1. Your morning routine (daily)

```
  YOU                                          SYSTEM
   |                                             |
   |  1. Open terminal, run:                     |
   |     python data_validation/                 |
   |            live_reconciliation.py           |
   |  ----------------------------------------> |
   |                                             |
   |            [1/11] Connect to BigQuery       |
   |            Checks database is reachable     |
   |            Shows last sync time per source  |
   |                                             |
   |            [2/11] Call Facebook API          |
   |            Gets real spend/clicks/views     |
   |            from Facebook directly           |
   |                                             |
   |            [3/11] Query Facebook in BigQuery |
   |            Gets same metrics from our DB    |
   |                                             |
   |            [4/11] Compare Facebook           |
   |  <-------- Shows side-by-side:              |
   |            API value vs DB value             |
   |            + MATCH or MISMATCH              |
   |                                             |
   |            [5/11] Call TikTok API            |
   |            Same thing for TikTok            |
   |                                             |
   |            [6/11] Query TikTok in BigQuery   |
   |                                             |
   |            [7/11] Compare TikTok             |
   |  <-------- API vs DB side-by-side           |
   |                                             |
   |            [8/11] Call Shopify API            |
   |            Gets order count + revenue       |
   |            from Shopify directly             |
   |                                             |
   |            [9/11] Query Shopify in BigQuery   |
   |                                             |
   |            [10/11] Compare Shopify            |
   |  <-------- Order count + revenue comparison |
   |                                             |
   |            [11/11] SCOREBOARD                |
   |  <======== Final result:                    |
   |            "8/8 MATCH" = ALL GOOD           |
   |            or shows which ones failed       |
   |                                             |
```

### What does each result mean?

| You see | Meaning | Action needed |
|---------|---------|---------------|
| **MATCH** (green) | Our database matches the ad platform | None - everything is correct |
| **MISMATCH** (red) | Numbers differ by more than 2% | See "If something fails" below |
| **SKIPPED** (yellow) | An account had no activity in the period | Normal for inactive accounts (e.g. Canada) |

### What it checks for each platform

For **Facebook** (3 accounts: US, Europe, Canada) and **TikTok**, it compares:
- **Spend** - money spent on ads
- **Impressions** - how many times ads were shown
- **Clicks** - how many people clicked

For **Shopify**, it compares:
- **Order Count** - number of orders in the period
- **Revenue** - total revenue (sum of total_price)

### Understanding the parameters

| Parameter | What it does | Default |
|-----------|-------------|---------|
| *(no parameter)* | Checks **all 3 platforms** for the last **14 days** | All platforms, 14 days, 2% tolerance |
| `--platform` | Choose which platform to check: `shopify`, `facebook`, `tiktok`, or `all` | `all` |
| `--days` | How many days to look back from today | `14` |
| `--start-date` | Start of the date range (format: `YYYY-MM-DD`). Overrides `--days` | *(auto-calculated)* |
| `--end-date` | End of the date range (format: `YYYY-MM-DD`) | *(2 days ago, to let attribution settle)* |
| `--tolerance` | Acceptable difference in percent. Below this = MATCH | `2` (= 2%) |
| `--no-animation` | Skip the visual animations (runs faster) | *(animations on)* |

---

## 2. If something fails (MISMATCH)

```
  MISMATCH seen
       |
       v
  Is the difference small (2-5%)?
       |              |
      YES             NO (big gap)
       |              |
       v              v
  NORMAL             Check Airbyte
  Attribution        (see section 5)
  window delay.        |
  Wait 24h and         v
  re-run.         Is the sync stuck?
                       |           |
                      YES          NO
                       |           |
                       v           v
                  Click          Contact
                  "Sync now"    the team
                  in Airbyte
```

### Quick diagnosis

| Symptom | Most likely cause | Fix |
|---------|-------------------|-----|
| Spend off by 1-3% | Normal rounding / attribution delay | Wait 24h, re-run |
| Spend off by 50%+ | Sync is stuck or failed | Open Airbyte, restart the sync |
| "API Error" in red | API token expired | Contact the team to refresh the token |
| "credentials not configured" | Missing config file | Contact the team |
| "FAILED: BigQuery" at step 1 | Not authenticated | Run `gcloud auth login` first |
| All TikTok = SKIPPED | TikTok token expired | Contact the team |
| Shopify "HTTP 401" | Shopify access token expired | Contact the team |
| Shopify order count = 0 | Date range has no orders | Try a wider date range (--days 30) |

---

## 3. First-time setup (one time only)

### Step 1: Install Google Cloud

Download and install from: **https://cloud.google.com/sdk/docs/install**

### Step 2: Log in (a browser window will open)

```
gcloud auth login
gcloud config set project hulken
gcloud auth application-default login
```

### Step 3: Install required tools

```
pip install google-cloud-bigquery pandas db-dtypes python-dotenv requests pyarrow streamlit
```

### Step 4: Verify it works

```
python data_validation/live_reconciliation.py --no-animation
```

If you see the scoreboard with results, you're ready.

---

## 4. Exploring the data

### Option A: BigQuery (in browser, nothing to install)

1. Go to **https://console.cloud.google.com/bigquery?project=hulken**
2. Left panel: click **hulken** > **ads_data**
3. Click any table > **Preview** tab to see the data

### Option B: Dashboard (visual, with CSV export)

```
streamlit run data_explorer.py
```

Opens http://localhost:8501 with ready-made reports and CSV download.

---

## 5. Restarting a stuck sync (Airbyte)

Only needed if the reconciliation shows a big MISMATCH or data is 2+ days old.

### Windows (PowerShell):
```
gcloud compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --ssh-flag="-L 8000:localhost:8000"
```

### Then:
1. Open **http://localhost:8000** in your browser
2. Get login credentials: run `abctl local credentials` on the VM
3. You see 3 connections: Facebook, Shopify, TikTok
4. Click the one that's stuck > **Sync now**
5. Wait: Facebook ~30 min, Shopify ~10 min, TikTok ~15 min

---

## 6. Available tables (reference)

| Table | What's inside |
|-------|---------------|
| `shopify_live_orders_clean` | Recent orders (price, date, currency) |
| `shopify_live_customers_clean` | Customer profiles (total spent, order count) |
| `shopify_utm` | Which ad/campaign led to each order |
| `shopify_orders` | Full order history since 2018 |
| `facebook_insights` | Facebook daily performance (spend, clicks, impressions) |
| `facebook_campaigns_daily` | Facebook performance grouped by campaign |
| `tiktok_ads_reports_daily` | TikTok daily performance |
| `tiktok_campaigns` | TikTok campaign names |

**Important:** Always use `_clean` tables for Shopify (privacy protection).

---

## 7. Common commands (copy-paste ready)

### Daily morning check (all platforms, last 14 days)
```
python data_validation/live_reconciliation.py
```

### Check only Shopify
```
python data_validation/live_reconciliation.py --platform shopify
```

### Check only Facebook
```
python data_validation/live_reconciliation.py --platform facebook
```

### Check only TikTok
```
python data_validation/live_reconciliation.py --platform tiktok
```

### Check a specific month (e.g. January 2026)
```
python data_validation/live_reconciliation.py --start-date 2026-01-01 --end-date 2026-01-31
```

### Check last 30 days instead of 14
```
python data_validation/live_reconciliation.py --days 30
```

### Check yesterday only
```
python data_validation/live_reconciliation.py --days 1
```

### Check one platform for a specific period
```
python data_validation/live_reconciliation.py --platform shopify --start-date 2026-02-01 --end-date 2026-02-10
```

### Allow 5% tolerance instead of 2%
```
python data_validation/live_reconciliation.py --tolerance 5
```

### Fast mode (no animation, for quick checks)
```
python data_validation/live_reconciliation.py --no-animation
```

### Combine options
```
python data_validation/live_reconciliation.py --platform facebook --days 30 --tolerance 5 --no-animation
```

---

## 8. Frequently Asked Questions (FAQ)

### How do I join Shopify, Facebook, TikTok tables together?

There is no direct key between ad platforms and Shopify orders. The link goes through UTM parameters:

```sql
-- Facebook campaign → Shopify orders (via UTM tracking)
SELECT
  u.first_utm_source,
  u.first_utm_campaign,
  COUNT(*) AS orders,
  SUM(CAST(o.total_price AS FLOAT64)) AS revenue
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_utm` u
  ON CAST(o.id AS STRING) = u.order_id
WHERE u.first_utm_source = 'facebook'
GROUP BY 1, 2
ORDER BY revenue DESC
```

```sql
-- Shopify orders → customers (via email_hash)
SELECT
  c.email_hash,
  c.orders_count,
  c.total_spent,
  COUNT(o.id) AS recent_orders
FROM `hulken.ads_data.shopify_live_customers_clean` c
JOIN `hulken.ads_data.shopify_live_orders_clean` o
  ON c.email_hash = o.email_hash
GROUP BY 1, 2, 3
```

**Summary of join keys:**

| Table A | Table B | Join key |
|---------|---------|----------|
| orders_clean | shopify_utm | `CAST(orders.id AS STRING) = utm.order_id` |
| orders_clean | customers_clean | `orders.email_hash = customers.email_hash` |
| orders_clean | shopify_line_items | `orders.id = line_items.order_id` |
| shopify_utm | facebook_insights | `utm.first_utm_campaign = insights.campaign_name` (approximate) |

---

### How do I rename a column or table from VSCode?

You cannot rename columns directly in BigQuery. Instead, create a **view** with the names you want:

```sql
CREATE OR REPLACE VIEW `hulken.ads_data.my_custom_orders` AS
SELECT
  id AS order_id,
  name AS order_name,
  total_price AS revenue,
  created_at AS order_date
FROM `hulken.ads_data.shopify_live_orders_clean`
```

The original table stays unchanged. Your view shows the columns with your preferred names.

---

### How do I modify files on GitHub?

Two options:

1. **From VSCode** (recommended): Edit files locally, then in the terminal:
   ```
   git add .
   git commit -m "description of changes"
   git push
   ```

2. **From GitHub directly**: Go to https://github.com/devops131326/Hulken_better_signal, click any file, click the pencil icon to edit, then "Commit changes".

---

### Where are Google Ads, Google Analytics? It's not clear

The project has **multiple datasets** (think of them as folders):

| Dataset | What's inside | Source |
|---------|--------------|--------|
| `hulken.ads_data` | Facebook, TikTok, Shopify | Airbyte (syncs every hour) |
| `hulken.google_Ads` | Google Ads campaigns, clicks, spend | Google Ads Data Transfer (daily) |
| `hulken.analytics_334792038` | Google Analytics (website 1) | GA4 BigQuery export (daily) |
| `hulken.analytics_454869667` | Google Analytics (website 2) | GA4 BigQuery export (daily) |
| `hulken.analytics_454871405` | Google Analytics (website 3) | GA4 BigQuery export (daily) |

In BigQuery console, expand **hulken** in the left panel to see all datasets.

**Note:** There is also an empty `hulken.google_ads` (lowercase) dataset — this is unused and can be ignored.

---

### Why didn't live_reconciliation detect that shopify_live_inventory_items was empty?

The live reconciliation script compares **API values vs BigQuery values** for 3 platforms (Facebook, TikTok, Shopify). It checks spend, impressions, clicks, order counts, and revenue.

It does **not** check whether every table has data. The `shopify_live_inventory_items` table is empty because that stream is **disabled** in Airbyte (intentionally — inventory data is not needed for analytics).

---

### If a new table gets added, how do we know?

Airbyte only syncs the streams that are **explicitly enabled** in each connection. New tables don't appear automatically.

To see what's currently synced:
1. Open Airbyte (see section 5 for access)
2. Click a connection (e.g. Shopify)
3. The **Streams** tab shows which tables are enabled

If Shopify adds a new data type, you need to enable the corresponding stream in Airbyte for it to appear in BigQuery.

---

### How do I add a new table to BigQuery?

**Option A — Enable a stream in Airbyte** (for data from Facebook/TikTok/Shopify):
1. Open Airbyte (see section 5)
2. Click the connection
3. In the Streams tab, enable the new stream
4. Click "Save" then "Sync now"
5. The table appears in `hulken.ads_data` after the sync completes

**Option B — Create manually** (for custom data):
```sql
CREATE TABLE `hulken.ads_data.my_new_table` (
  id INT64,
  name STRING,
  value FLOAT64,
  created_at TIMESTAMP
)
```

---

### Where is the conversion rate in Facebook tables?

Facebook does **not** provide a "conversion rate" as a single number. It provides raw components that you calculate yourself:

```sql
-- Calculate conversion rate from Facebook data
SELECT
  date_start,
  campaign_name,
  CAST(spend AS FLOAT64) AS spend,
  clicks,
  impressions,
  -- CTR (Click-Through Rate)
  ROUND(SAFE_DIVIDE(clicks, impressions) * 100, 2) AS ctr_pct,
  -- CPC (Cost Per Click)
  ROUND(SAFE_DIVIDE(CAST(spend AS FLOAT64), clicks), 2) AS cpc
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= '2026-01-01'
ORDER BY date_start DESC
```

For **purchase conversions** specifically, the data is in the `actions` column (JSON format). The `facebook_ads_insights_action_type` table will have this broken out when the sync completes.

---

### Why is `google_ads` (lowercase) not deleted?

The `hulken.google_ads` dataset (lowercase 'a') is **empty** (0 tables). It was probably created by mistake. The real Google Ads data lives in `hulken.google_Ads` (uppercase 'A', 190 tables).

The empty one should be deleted — contact the team or run:
```sql
-- This requires dataset admin permissions
DROP SCHEMA `hulken.google_ads`
```

---

### What should we clean up / delete?

**Safe to delete** (empty or unused):
- `hulken.google_ads` — empty dataset (0 tables), the real one is `google_Ads`
- `hulken.ads_data.shopify_live_inventory_items` — 0 rows, stream disabled in Airbyte

**Do NOT delete** (looks confusing but is needed):
- Raw Airbyte tables (`shopify_live_orders`, `shopify_live_customers`, etc.) — Airbyte writes to these
- `airbyte_internal` dataset — used by Airbyte for internal state

---

### How do I standardize / rename columns across tables?

Create **views** with your standardized column names. Example:

```sql
CREATE OR REPLACE VIEW `hulken.ads_data.v_orders_standard` AS
SELECT
  id AS index_id,
  total_price AS target_revenue,
  source_name AS feature_channel,
  created_at AS feature_date
FROM `hulken.ads_data.shopify_live_orders_clean`
```

Views don't copy data — they are just a "rename layer" on top of the real table. You can create as many views as you want without using extra storage.

---

### When there are differences (MISMATCH), what should I do?

See **section 2** of this guide for the complete diagnosis flowchart. In short:

| Difference | Cause | Action |
|-----------|-------|--------|
| 1-3% | Normal attribution delay | Wait 24h, re-run |
| 3-10% | Sync is behind / catching up | Check Airbyte, sync may be running |
| 50%+ | Sync failed or stuck | Restart in Airbyte (section 5) |
| API Error | Token expired | Contact the team |

---

### Why does live_reconciliation show different values than BigQuery?

The script compares **specific date ranges** with a **2-day exclusion** by default (to let Facebook attribution settle). If you query BigQuery manually without the same date filters, numbers will differ.

To match exactly, use the same dates:
```
python data_validation/live_reconciliation.py --start-date 2026-02-01 --end-date 2026-02-10 --no-animation
```
Then run the same query in BigQuery:
```sql
SELECT SUM(CAST(spend AS FLOAT64)) FROM `hulken.ads_data.facebook_insights`
WHERE date_start BETWEEN '2026-02-01' AND '2026-02-10'
AND account_id = '440461496366294'
```

---

### Why do different customers have the same first_name_hash or phone_hash?

This is **normal** — it means they share the same first name (or phone number). For example, many customers are named "John" or "Sarah", so their `first_name_hash` will be identical.

The hash `e3b0c44298fc1c14...7852b855` specifically means **empty string** — these are customers where the field was blank.

**Note:** 121 customers share the "empty" first_name_hash. This is not a bug — it means their first name was empty in Shopify.

---

### Why is total_spent = 0 for some customers?

**30% of customers** (7,351 / 23,743) show `total_spent = 0`. This is a **known Shopify API limitation**:

- The Shopify API returns `total_spent = 0` for customers who were created **before** the sync window
- Airbyte syncs customers incrementally, so old customers get `0` because Shopify doesn't recalculate historical values for API responses
- The actual spending data is in the **orders table** — you can calculate it:

```sql
-- Real total spent per customer
SELECT
  c.id,
  c.total_spent AS shopify_says,
  COALESCE(SUM(CAST(o.total_price AS FLOAT64)), 0) AS real_total_spent
FROM `hulken.ads_data.shopify_live_customers_clean` c
LEFT JOIN `hulken.ads_data.shopify_live_orders_clean` o
  ON c.email_hash = o.email_hash
GROUP BY 1, 2
ORDER BY real_total_spent DESC
```

---

### Why is orders_count = 0 for some customers?

Same reason as `total_spent = 0` above — **30% of customers** (7,159 / 23,743) show 0. This is a Shopify API limitation, not a data bug. Use the orders table to get the real count.

---

### Why are there two order name formats: #595395 vs X-566085-1?

| Format | Meaning | Count |
|--------|---------|-------|
| `#595395` | **Standard order** (web, POS, or API) | 42,218 (99%) |
| `X-566085-1` | **Exchange order** (customer exchanged a product) | 447 (1%) |

Exchange orders are created automatically by Shopify when a customer returns a product and gets a replacement. The `X-` prefix and the `-1` suffix indicate it's linked to original order `#566085`.

---

## 9. Quick reference

```
Morning check    : python data_validation/live_reconciliation.py
Shopify only     : python data_validation/live_reconciliation.py --platform shopify
Custom dates     : python data_validation/live_reconciliation.py --start-date 2026-01-01 --end-date 2026-01-31
Dashboard        : streamlit run data_explorer.py
BigQuery console : https://console.cloud.google.com/bigquery?project=hulken
Re-authenticate  : gcloud auth login
```
