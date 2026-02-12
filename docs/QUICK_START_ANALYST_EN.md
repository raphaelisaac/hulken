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

## 8. Quick reference

```
Morning check    : python data_validation/live_reconciliation.py
Shopify only     : python data_validation/live_reconciliation.py --platform shopify
Custom dates     : python data_validation/live_reconciliation.py --start-date 2026-01-01 --end-date 2026-01-31
Dashboard        : streamlit run data_explorer.py
BigQuery console : https://console.cloud.google.com/bigquery?project=hulken
Re-authenticate  : gcloud auth login
```
