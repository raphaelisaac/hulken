# Query Library - Hulken Analytics

**Dernière mise à jour:** 2026-02-04
**Projet:** hulken.ads_data

---

## 1. Revenue & Attribution

### 1.1 Revenue par Canal UTM

```sql
SELECT
  first_utm_source as channel,
  COUNT(DISTINCT order_id) as orders,
  SUM(total_price) as revenue,
  AVG(total_price) as aov
FROM `hulken.ads_data.shopify_utm`
WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
```

### 1.2 Revenue par Campagne

```sql
SELECT
  first_utm_campaign as campaign,
  first_utm_source as source,
  COUNT(DISTINCT order_id) as orders,
  SUM(total_price) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_campaign IS NOT NULL
  AND created_at >= '2026-01-01'
GROUP BY 1, 2
ORDER BY revenue DESC
LIMIT 50
```

### 1.3 Attribution par Jour

```sql
SELECT
  DATE(created_at) as date,
  attribution_status,
  COUNT(*) as orders,
  SUM(total_price) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
ORDER BY 1
```

---

## 2. Facebook Ads

### 2.1 Performance Campagnes

```sql
SELECT
  campaign_name,
  SUM(spend) as spend,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks,
  SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100 as ctr,
  SAFE_DIVIDE(SUM(spend), SUM(clicks)) as cpc
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

### 2.2 ROAS Facebook

```sql
WITH fb_spend AS (
  SELECT
    campaign_name,
    SUM(spend) as spend
  FROM `hulken.ads_data.facebook_insights`
  WHERE date_start >= '2026-01-01'
  GROUP BY 1
),
shopify_revenue AS (
  SELECT
    first_utm_campaign as campaign_name,
    SUM(total_price) as revenue,
    COUNT(DISTINCT order_id) as orders
  FROM `hulken.ads_data.shopify_utm`
  WHERE first_utm_source LIKE '%facebook%'
    AND created_at >= '2026-01-01'
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

### 2.3 Performance par Pays

```sql
SELECT
  country,
  SUM(spend) as spend,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks
FROM `hulken.ads_data.facebook_insights_country`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

---

## 3. TikTok Ads

### 3.1 Performance Campagnes

```sql
SELECT
  campaign_name,
  SUM(spend) as spend,
  SUM(impressions) as impressions,
  SUM(clicks) as clicks,
  SUM(conversion) as conversions,
  SAFE_DIVIDE(SUM(conversion), SUM(clicks)) * 100 as cvr
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE stat_time_day >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY spend DESC
```

### 3.2 ROAS TikTok

```sql
WITH tiktok_spend AS (
  SELECT
    campaign_name,
    SUM(spend) as spend,
    SUM(conversion) as conversions
  FROM `hulken.ads_data.tiktok_ads_reports_daily`
  WHERE stat_time_day >= '2026-01-01'
  GROUP BY 1
),
shopify_revenue AS (
  SELECT
    first_utm_campaign as campaign_name,
    SUM(total_price) as revenue,
    COUNT(DISTINCT order_id) as orders
  FROM `hulken.ads_data.shopify_utm`
  WHERE first_utm_source LIKE '%tiktok%'
    AND created_at >= '2026-01-01'
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

### 4.1 LTV par Canal d'Acquisition

```sql
WITH first_order AS (
  SELECT
    email_hash,
    MIN(created_at) as first_order_date,
    ANY_VALUE(first_utm_source) as acquisition_channel
  FROM `hulken.ads_data.shopify_utm` u
  JOIN `hulken.ads_data.shopify_orders` o ON u.order_id = o.id
  WHERE email_hash IS NOT NULL
  GROUP BY 1
),
all_orders AS (
  SELECT
    o.email_hash,
    SUM(o.total_price) as lifetime_value,
    COUNT(*) as order_count
  FROM `hulken.ads_data.shopify_orders` o
  WHERE email_hash IS NOT NULL
  GROUP BY 1
)
SELECT
  f.acquisition_channel,
  COUNT(DISTINCT f.email_hash) as customers,
  AVG(a.lifetime_value) as avg_ltv,
  AVG(a.order_count) as avg_orders
FROM first_order f
JOIN all_orders a ON f.email_hash = a.email_hash
GROUP BY 1
ORDER BY avg_ltv DESC
```

### 4.2 Cohort Analysis

```sql
SELECT
  DATE_TRUNC(first_order_date, MONTH) as cohort_month,
  COUNT(DISTINCT email_hash) as customers,
  SUM(total_orders) as total_orders,
  SUM(total_revenue) as total_revenue
FROM (
  SELECT
    email_hash,
    MIN(created_at) as first_order_date,
    COUNT(*) as total_orders,
    SUM(total_price) as total_revenue
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
  SUM(total_spent) as revenue
FROM (
  SELECT
    email_hash,
    COUNT(*) as order_count,
    SUM(total_price) as total_spent
  FROM `hulken.ads_data.shopify_orders`
  WHERE email_hash IS NOT NULL
  GROUP BY 1
)
GROUP BY 1
ORDER BY 1
```

---

## 5. Product Analytics

### 5.1 Top Produits

```sql
SELECT
  JSON_VALUE(li, '$.title') as product,
  COUNT(*) as units_sold,
  SUM(CAST(JSON_VALUE(li, '$.price') AS FLOAT64)) as revenue
FROM `hulken.ads_data.shopify_live_orders`,
UNNEST(JSON_QUERY_ARRAY(line_items)) as li
WHERE created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
LIMIT 20
```

---

## 6. Data Quality & Diagnostics

### 6.1 Fraîcheur des Données

```sql
SELECT
  'shopify_live_orders' as source,
  MAX(_airbyte_extracted_at) as last_sync,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_airbyte_extracted_at), HOUR) as hours_ago
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'facebook_insights', MAX(_airbyte_extracted_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_airbyte_extracted_at), HOUR)
FROM `hulken.ads_data.facebook_insights`
UNION ALL
SELECT 'tiktok_ads_reports_daily', MAX(_airbyte_extracted_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_airbyte_extracted_at), HOUR)
FROM `hulken.ads_data.tiktok_ads_reports_daily`
UNION ALL
SELECT 'shopify_utm', MAX(extracted_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(extracted_at), HOUR)
FROM `hulken.ads_data.shopify_utm`
```

### 6.2 Vérification PII

```sql
SELECT
  'shopify_live_orders' as tbl,
  COUNTIF(email IS NOT NULL) as emails_exposed,
  COUNTIF(phone IS NOT NULL) as phones_exposed,
  COUNT(*) as total
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'shopify_live_customers',
  COUNTIF(email IS NOT NULL),
  COUNTIF(phone IS NOT NULL),
  COUNT(*)
FROM `hulken.ads_data.shopify_live_customers`
```

### 6.3 Doublons UTM

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

### 6.4 Couverture Attribution

```sql
SELECT
  attribution_status,
  COUNT(*) as orders,
  SUM(total_price) as revenue,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
ORDER BY orders DESC
```

### 6.5 Row Counts par Table

```sql
SELECT 'shopify_orders' as tbl, COUNT(*) as rows FROM `hulken.ads_data.shopify_orders`
UNION ALL SELECT 'shopify_utm', COUNT(*) FROM `hulken.ads_data.shopify_utm`
UNION ALL SELECT 'shopify_live_orders', COUNT(*) FROM `hulken.ads_data.shopify_live_orders`
UNION ALL SELECT 'facebook_insights', COUNT(*) FROM `hulken.ads_data.facebook_insights`
UNION ALL SELECT 'tiktok_ads_reports_daily', COUNT(*) FROM `hulken.ads_data.tiktok_ads_reports_daily`
ORDER BY rows DESC
```

---

## 7. Cross-Platform Comparisons

### 7.1 Spend par Plateforme

```sql
SELECT
  'Facebook' as platform,
  SUM(spend) as spend,
  'EUR' as currency
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
UNION ALL
SELECT
  'TikTok',
  SUM(spend),
  'USD'
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE stat_time_day >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

### 7.2 Revenue Attribué par Plateforme

```sql
SELECT
  first_utm_source as platform,
  COUNT(DISTINCT order_id) as orders,
  SUM(total_price) as revenue,
  AVG(total_price) as aov
FROM `hulken.ads_data.shopify_utm`
WHERE first_utm_source IN ('facebook', 'tiktok', 'google', 'instagram')
  AND created_at >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY revenue DESC
```

---

*Bibliothèque consolidée le 2026-02-04*
*Fusion de: COMMON_QUERIES, CROSS_PLATFORM_MATCHING_GUIDE, diagnostics de TROUBLESHOOTING*
