# Query Library - Hulken Analytics

**Last updated:** 2026-02-10
**Project:** hulken.ads_data, google_Ads

---

## 1. Revenue & Attribution

### 1.1 Revenue by UTM Channel

```sql
SELECT
  first_utm_source as channel,
  COUNT(DISTINCT order_id) as orders,
  ROUND(SUM(total_price), 2) as revenue,
  ROUND(AVG(total_price), 2) as aov
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
```

### 1.2 Revenue by Campaign

```sql
SELECT
  first_utm_campaign as campaign,
  first_utm_source as source,
  COUNT(DISTINCT order_id) as orders,
  ROUND(SUM(total_price), 2) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_campaign IS NOT NULL
  AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
ORDER BY revenue DESC
LIMIT 50
```

### 1.3 Attribution by Day

```sql
SELECT
  DATE(created_at) as date,
  attribution_status,
  COUNT(*) as orders,
  ROUND(SUM(total_price), 2) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
ORDER BY 1
```

---

## 2. Facebook Ads

> **3 accounts available:** Hulken (US, $8M total), Hulken Europe ($345K), Hulken Canada (stopped Dec 2024)
> Filter by region: `WHERE account_name = 'Hulken'` (US) or `WHERE account_name = 'Hulken Europe'`

### 2.1 Campaign Performance (daily)

```sql
-- Uses facebook_campaigns_daily view (aggregated by campaign/day)
SELECT
  campaign_name,
  account_name,
  date_start,
  spend,
  impressions,
  clicks,
  SAFE_DIVIDE(clicks, impressions) * 100 as ctr,
  SAFE_DIVIDE(spend, clicks) as cpc,
  ad_count
FROM `hulken.ads_data.facebook_campaigns_daily`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
ORDER BY spend DESC
```

### 2.2 Campaign Performance (aggregated)

```sql
SELECT
  campaign_name,
  account_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as spend,
  SUM(CAST(impressions AS INT64)) as impressions,
  SUM(CAST(clicks AS INT64)) as clicks,
  SAFE_DIVIDE(SUM(CAST(clicks AS INT64)), SUM(CAST(impressions AS INT64))) * 100 as ctr,
  SAFE_DIVIDE(SUM(CAST(spend AS FLOAT64)), SUM(CAST(clicks AS INT64))) as cpc
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
ORDER BY spend DESC
```

### 2.3 ROAS Facebook

```sql
WITH fb_spend AS (
  SELECT
    campaign_name,
    ROUND(SUM(CAST(spend AS FLOAT64)), 2) as spend
  FROM `hulken.ads_data.facebook_insights`
  WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY 1
),
shopify_revenue AS (
  SELECT
    first_utm_campaign as campaign_name,
    ROUND(SUM(total_price), 2) as revenue,
    COUNT(DISTINCT order_id) as orders
  FROM `hulken.ads_data.shopify_utm`
  WHERE first_utm_source LIKE '%facebook%'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY 1
)
SELECT
  COALESCE(f.campaign_name, s.campaign_name) as campaign,
  f.spend,
  s.revenue,
  s.orders,
  SAFE_DIVIDE(s.revenue, f.spend) as roas
FROM fb_spend f
FULL OUTER JOIN shopify_revenue s ON f.campaign_name = s.campaign_name
WHERE f.spend > 0 OR s.revenue > 0
ORDER BY f.spend DESC NULLS LAST
```

### 2.4 Performance by Country

```sql
SELECT
  country,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as spend,
  SUM(CAST(impressions AS INT64)) as impressions,
  SUM(CAST(clicks AS INT64)) as clicks
FROM `hulken.ads_data.facebook_insights_country`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

### 2.5 Performance by Account (US vs EU vs CA)

```sql
SELECT
  account_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as spend,
  SUM(CAST(impressions AS INT64)) as impressions,
  SUM(CAST(clicks AS INT64)) as clicks,
  MIN(date_start) as first_date,
  MAX(date_start) as last_date
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

---

## 3. TikTok Ads

> TikTok view `tiktok_ads_reports_daily` has flat columns: spend, impressions, clicks, conversions, report_date
> Campaign name requires JOIN: reports -> tiktokads (ad_id) -> tiktokcampaigns (campaign_id)

### 3.1 Campaign Performance

```sql
-- Join chain: reports -> ads -> campaigns (campaign_id is NULL in reports)
SELECT
  c.campaign_name,
  ROUND(SUM(r.spend), 2) as spend,
  SUM(r.impressions) as impressions,
  SUM(r.clicks) as clicks,
  SUM(r.conversions) as conversions,
  SAFE_DIVIDE(SUM(r.conversions), SUM(r.clicks)) * 100 as cvr
FROM `hulken.ads_data.tiktok_ads_reports_daily` r
JOIN `hulken.ads_data.tiktokads` a ON r.ad_id = a.ad_id
JOIN `hulken.ads_data.tiktokcampaigns` c ON a.campaign_id = c.campaign_id
WHERE r.report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

### 3.1b Daily Spend (no join needed)

```sql
SELECT
  report_date as date,
  ROUND(SUM(spend), 2) as spend,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks,
  SUM(conversions) as conversions
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

### 3.2 ROAS TikTok

```sql
WITH tiktok_spend AS (
  SELECT
    c.campaign_name,
    ROUND(SUM(r.spend), 2) as spend,
    SUM(r.conversions) as conversions
  FROM `hulken.ads_data.tiktok_ads_reports_daily` r
  JOIN `hulken.ads_data.tiktokads` a ON r.ad_id = a.ad_id
  JOIN `hulken.ads_data.tiktokcampaigns` c ON a.campaign_id = c.campaign_id
  WHERE r.report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY 1
),
shopify_revenue AS (
  SELECT
    first_utm_campaign as campaign_name,
    ROUND(SUM(total_price), 2) as revenue,
    COUNT(DISTINCT order_id) as orders
  FROM `hulken.ads_data.shopify_utm`
  WHERE first_utm_source LIKE '%tiktok%'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY 1
)
SELECT
  COALESCE(t.campaign_name, s.campaign_name) as campaign,
  t.spend,
  t.conversions as tiktok_conversions,
  s.revenue,
  s.orders as shopify_orders,
  SAFE_DIVIDE(s.revenue, t.spend) as roas
FROM tiktok_spend t
FULL OUTER JOIN shopify_revenue s ON t.campaign_name = s.campaign_name
ORDER BY t.spend DESC NULLS LAST
```

---

## 4. Customer Analytics

### 4.1 LTV by Acquisition Channel

```sql
-- Joins shopify_utm -> shopify_orders via order_id to get customer_id
WITH first_order AS (
  SELECT
    o.customer_id,
    MIN(DATE(u.created_at)) as first_order_date,
    ANY_VALUE(u.first_utm_source) as acquisition_channel
  FROM `hulken.ads_data.shopify_utm` u
  JOIN `hulken.ads_data.shopify_orders` o ON u.order_id = o.id
  WHERE o.customer_id IS NOT NULL
  GROUP BY 1
),
all_orders AS (
  SELECT
    customer_id,
    ROUND(SUM(totalPrice), 2) as lifetime_value,
    COUNT(*) as order_count
  FROM `hulken.ads_data.shopify_orders`
  WHERE customer_id IS NOT NULL
  GROUP BY 1
)
SELECT
  f.acquisition_channel,
  COUNT(DISTINCT f.customer_id) as customers,
  ROUND(AVG(a.lifetime_value), 2) as avg_ltv,
  ROUND(AVG(a.order_count), 1) as avg_orders
FROM first_order f
JOIN all_orders a ON f.customer_id = a.customer_id
GROUP BY 1
ORDER BY avg_ltv DESC
```

### 4.2 Cohort Analysis

```sql
SELECT
  DATE_TRUNC(first_order_date, MONTH) as cohort_month,
  COUNT(DISTINCT email_hash) as customers,
  SUM(total_orders) as total_orders,
  ROUND(SUM(total_revenue), 2) as total_revenue
FROM (
  SELECT
    email_hash,
    MIN(DATE(createdAt)) as first_order_date,
    COUNT(*) as total_orders,
    SUM(totalPrice) as total_revenue
  FROM `hulken.ads_data.shopify_orders`
  WHERE email_hash IS NOT NULL
  GROUP BY 1
)
GROUP BY 1
ORDER BY 1
```

### 4.3 Repeat Purchase Rate

```sql
SELECT
  CASE
    WHEN order_count = 1 THEN '1 order'
    WHEN order_count = 2 THEN '2 orders'
    WHEN order_count BETWEEN 3 AND 5 THEN '3-5 orders'
    ELSE '6+ orders'
  END as segment,
  COUNT(*) as customers,
  ROUND(SUM(total_spent), 2) as revenue
FROM (
  SELECT
    email_hash,
    COUNT(*) as order_count,
    SUM(totalPrice) as total_spent
  FROM `hulken.ads_data.shopify_orders`
  WHERE email_hash IS NOT NULL
  GROUP BY 1
)
GROUP BY 1
ORDER BY 1
```

---

## 5. Product Analytics

### 5.1 Top Products (from line items)

```sql
SELECT
  title as product,
  SUM(quantity) as units_sold,
  ROUND(SUM(originalTotal), 2) as revenue
FROM `hulken.ads_data.shopify_line_items`
GROUP BY 1
ORDER BY revenue DESC
LIMIT 20
```

### 5.2 Top Products (last 30 days, from live orders)

```sql
SELECT
  JSON_VALUE(li, '$.title') as product,
  COUNT(*) as units_sold,
  ROUND(SUM(CAST(JSON_VALUE(li, '$.price') AS FLOAT64)), 2) as revenue
FROM `hulken.ads_data.shopify_live_orders_clean`,
UNNEST(JSON_QUERY_ARRAY(line_items)) as li
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
LIMIT 20
```

---

## 6. Data Quality & Diagnostics

### 6.1 Data Freshness

```sql
SELECT 'facebook_ads' AS source, MAX(date_start) AS latest,
  DATE_DIFF(CURRENT_DATE(), MAX(date_start), DAY) AS days_behind
FROM `hulken.ads_data.facebook_insights`
UNION ALL
SELECT 'tiktok_ads', MAX(report_date),
  DATE_DIFF(CURRENT_DATE(), MAX(report_date), DAY)
FROM `hulken.ads_data.tiktok_ads_reports_daily`
UNION ALL
SELECT 'shopify_orders', MAX(DATE(created_at)),
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(created_at)), DAY)
FROM `hulken.ads_data.shopify_live_orders_clean`
UNION ALL
SELECT 'shopify_utm', MAX(DATE(created_at)),
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(created_at)), DAY)
FROM `hulken.ads_data.shopify_utm`
ORDER BY source
```

> **Automated alternative:** `python data_validation/reconciliation_check.py --checks freshness,sync_lag`

### 6.2 PII Audit

```sql
SELECT
  'shopify_live_orders' as tbl,
  COUNTIF(email IS NOT NULL AND email LIKE '%@%') as emails_exposed,
  COUNTIF(phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3) as phones_exposed,
  COUNT(*) as total
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'shopify_live_customers',
  COUNTIF(email IS NOT NULL AND email LIKE '%@%'),
  COUNTIF(phone IS NOT NULL AND phone != '' AND LENGTH(phone) > 3),
  COUNT(*)
FROM `hulken.ads_data.shopify_live_customers`
```

> Expected: 0 emails/phones exposed (PII hash job runs every 5 min)

### 6.3 UTM Duplicates

```sql
SELECT
  order_id,
  COUNT(*) as duplicates
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
HAVING COUNT(*) > 1
ORDER BY duplicates DESC
LIMIT 100
```

### 6.4 Attribution Coverage

```sql
SELECT
  attribution_status,
  COUNT(*) as orders,
  ROUND(SUM(total_price), 2) as revenue,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
ORDER BY orders DESC
```

### 6.5 Row Counts

```sql
SELECT 'shopify_orders' as tbl, COUNT(*) as rows FROM `hulken.ads_data.shopify_orders`
UNION ALL SELECT 'shopify_utm', COUNT(*) FROM `hulken.ads_data.shopify_utm`
UNION ALL SELECT 'shopify_live_orders_clean', COUNT(*) FROM `hulken.ads_data.shopify_live_orders_clean`
UNION ALL SELECT 'facebook_insights', COUNT(*) FROM `hulken.ads_data.facebook_insights`
UNION ALL SELECT 'tiktok_ads_reports_daily', COUNT(*) FROM `hulken.ads_data.tiktok_ads_reports_daily`
ORDER BY rows DESC
```

---

## 7. Cross-Platform Comparisons

### 7.1 Spend by Platform (last 30 days)

```sql
SELECT 'Facebook' as platform,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as spend
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
UNION ALL
SELECT 'TikTok',
  ROUND(SUM(spend), 2)
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
UNION ALL
SELECT 'Google Ads',
  ROUND(SUM(metrics_cost_micros) / 1e6, 2)
FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`
WHERE _DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

### 7.2 Attributed Revenue by Platform

```sql
SELECT
  first_utm_source as platform,
  COUNT(DISTINCT order_id) as orders,
  ROUND(SUM(total_price), 2) as revenue,
  ROUND(AVG(total_price), 2) as aov
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_source IN ('facebook', 'tiktok', 'google', 'instagram')
  AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
```

### 7.3 Daily Cross-Platform Dashboard

```sql
WITH daily_fb AS (
  SELECT date_start AS dt, ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend
  FROM `hulken.ads_data.facebook_insights`
  GROUP BY 1
),
daily_tt AS (
  SELECT report_date AS dt, ROUND(SUM(spend), 2) AS spend
  FROM `hulken.ads_data.tiktok_ads_reports_daily`
  GROUP BY 1
),
daily_gads AS (
  SELECT _DATA_DATE AS dt, ROUND(SUM(metrics_cost_micros) / 1e6, 2) AS spend
  FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`
  GROUP BY 1
),
daily_rev AS (
  SELECT DATE(created_at) AS dt,
    ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS revenue,
    COUNT(*) AS orders
  FROM `hulken.ads_data.shopify_live_orders_clean`
  GROUP BY 1
)
SELECT
  r.dt AS date,
  r.orders,
  r.revenue,
  COALESCE(f.spend, 0) AS facebook_spend,
  COALESCE(t.spend, 0) AS tiktok_spend,
  COALESCE(g.spend, 0) AS google_spend,
  COALESCE(f.spend, 0) + COALESCE(t.spend, 0) + COALESCE(g.spend, 0) AS total_spend,
  ROUND(SAFE_DIVIDE(r.revenue, COALESCE(f.spend,0) + COALESCE(t.spend,0) + COALESCE(g.spend,0)), 2) AS roas
FROM daily_rev r
LEFT JOIN daily_fb f ON r.dt = f.dt
LEFT JOIN daily_tt t ON r.dt = t.dt
LEFT JOIN daily_gads g ON r.dt = g.dt
WHERE r.dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY r.dt DESC
```

---

## 8. Google Ads

### 8.1 Daily Spend

```sql
SELECT
  _DATA_DATE AS date,
  ROUND(SUM(metrics_cost_micros) / 1e6, 2) AS spend_usd,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_clicks) AS clicks,
  ROUND(SUM(metrics_conversions_value), 2) AS conversion_value
FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`
WHERE _DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

### 8.2 Campaign Performance

```sql
SELECT
  c.campaign_name,
  ROUND(SUM(s.metrics_cost_micros) / 1e6, 2) AS spend_usd,
  SUM(s.metrics_impressions) AS impressions,
  SUM(s.metrics_clicks) AS clicks,
  ROUND(SUM(s.metrics_conversions), 1) AS conversions
FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000` s
JOIN `hulken.google_Ads.ads_Campaign_4354001000` c
  ON s.campaign_id = c.campaign_id
WHERE s._DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend_usd DESC
```

---

*Query Library consolidated 2026-02-10*
*All queries tested against live BigQuery data*
