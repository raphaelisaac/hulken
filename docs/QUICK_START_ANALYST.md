# Quick Start - BigQuery Analyst Guide

## Setup (one time)
```
setup_colleague_vscode.bat
```

## Project Structure
- **Project**: `hulken`
- **Main dataset**: `ads_data` (Shopify, Facebook, TikTok)
- **GA4 datasets**: `analytics_334792038` (EU), `analytics_454869667` (US), `analytics_454871405` (CA)

## Key Tables

| Table | Description | Key Fields |
|-------|-------------|------------|
| `shopify_live_orders_clean` | Orders (PII-safe) | id, total_price, created_at, email_hash, currency |
| `shopify_live_customers_clean` | Customers (PII-safe) | id, email_hash, total_spent, orders_count |
| `shopify_orders` | Historical orders (GraphQL) | id, totalPrice, createdAt, email_hash |
| `shopify_utm` | UTM attribution | order_id, first_utm_source, first_utm_campaign |
| `facebook_ads_insights` | Facebook ad metrics | ad_id, date_start, spend, impressions, clicks |
| `tiktok_ads_reports_daily` | TikTok ad metrics | ad_id, stat_time_day, metrics (JSON) |

## Important: Deduplication

Facebook data has duplicates from overlapping syncs. Always use this pattern:

```sql
WITH deduped_facebook AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY ad_id, date_start
    ORDER BY _airbyte_extracted_at DESC
  ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights`
)
SELECT * FROM deduped_facebook WHERE rn = 1
```

## Common Queries

### Daily Revenue
```sql
SELECT DATE(created_at) AS date,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY date ORDER BY date DESC
```

### Facebook Spend by Campaign (deduplicated)
```sql
WITH deduped AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY ad_id, date_start ORDER BY _airbyte_extracted_at DESC
  ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights`
  WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)
SELECT campaign_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend,
  SUM(CAST(impressions AS INT64)) AS impressions,
  SUM(CAST(clicks AS INT64)) AS clicks
FROM deduped WHERE rn = 1
GROUP BY campaign_name ORDER BY spend DESC
```

### TikTok Daily Spend
```sql
SELECT DATE(stat_time_day) AS date,
  ROUND(SUM(CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64)), 2) AS spend,
  SUM(CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64)) AS impressions
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE DATE(stat_time_day) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY date ORDER BY date DESC
```

### UTM Attribution - Revenue by Source
```sql
SELECT first_utm_source,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND first_utm_source IS NOT NULL
GROUP BY first_utm_source ORDER BY revenue DESC
```

### Cross-Platform Customer Match
```sql
-- Match orders to customers using email_hash
SELECT o.id AS order_id, o.total_price, o.created_at,
  c.total_spent AS customer_lifetime_value, c.orders_count
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_live_customers_clean` c
  ON o.email_hash = c.email_hash
WHERE DATE(o.created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
ORDER BY o.created_at DESC
LIMIT 100
```

## Export to CSV (Python)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')
query = "SELECT * FROM `hulken.ads_data.shopify_live_orders_clean` LIMIT 1000"
df = client.query(query).to_dataframe()
df.to_csv('orders_export.csv', index=False)
print(f"Exported {len(df)} rows")
```

## Data Health Check

Run the reconciliation check to verify data integrity:
```
python data_validation/reconciliation_check.py
```

Run specific checks only:
```
python data_validation/reconciliation_check.py --checks freshness,pii
```
