-- ============================================================
-- UNIFIED TABLES CREATION
-- ============================================================
-- Creates unified tables following the index/feature/target structure
-- defined in the labeling document.
--
-- Execution order:
--   1. shopify_unified (all Shopify tables merged)
--   2. facebook_unified (all Facebook metrics)
--   3. tiktok_unified (all TikTok metrics)
--   4. marketing_unified (ALL sources combined)
--
-- Usage:
--   Execute each section in BigQuery Console
--   Or execute all at once (takes ~5-10 minutes)
--
-- Created: 2026-02-13
-- ============================================================


-- ============================================================
-- PART 1: SHOPIFY UNIFIED
-- ============================================================
-- Merges all Shopify tables according to defined indexes:
--   - shopify_live_orders_clean (base)
--   - shopify_live_customers_clean (via email_hash)
--   - shopify_live_items (via order_id)
--   - shopify_live_transactions (via order_id)
--   - shopify_utm (via order_id)
--   - shopify_live_order_refunds (via order_id)

CREATE OR REPLACE TABLE `hulken.ads_data.shopify_unified` AS

WITH orders_base AS (
  SELECT
    -- ========== INDEXES ==========
    id AS order_id,
    CAST(REGEXP_EXTRACT(admin_graphql_api_id, r'(\d+)') AS INT64) AS order_id_numeric,
    email_hash AS order_email_hash,
    DATE(created_at) AS order_date,

    -- Order name standardization
    CASE
      WHEN name LIKE '#%' THEN REGEXP_EXTRACT(name, r'#(\d+)')
      WHEN name LIKE 'X-%' THEN REGEXP_EXTRACT(name, r'X-(\d+)')
      ELSE name
    END AS order_number_clean,

    -- ========== GROUPBY FEATURES ==========
    source_name,
    financial_status,
    fulfillment_status,

    -- ========== FEATURES ==========
    name AS order_name,
    created_at AS order_created_at,
    processed_at AS order_processed_at,
    cancelled_at AS order_cancelled_at,
    closed_at AS order_closed_at,
    cancel_reason,
    tags AS order_tags,
    currency AS order_currency,
    landing_site,
    referring_site,

    -- Customer reference (will be enhanced with customer table)
    user_id AS shopify_customer_id,

    -- ========== TARGETS ==========
    CAST(total_price AS FLOAT64) AS order_value,
    CAST(total_line_items_price AS FLOAT64) AS order_subtotal,
    CAST(current_total_discounts AS FLOAT64) AS order_discounts,
    CAST(total_tax AS FLOAT64) AS order_tax,
    CAST(total_shipping_price_set AS STRING) AS shipping_info,

    -- Line items count (will be enhanced with items table)
    0 AS items_count_placeholder,

    -- ========== METADATA ==========
    _airbyte_extracted_at AS order_last_sync_at

  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE created_at IS NOT NULL
),

customers_enhanced AS (
  SELECT
    -- ========== INDEXES ==========
    id AS customer_id,
    email_hash AS customer_email_hash,

    -- ========== GROUPBY FEATURES ==========
    state AS customer_state,

    -- ========== FEATURES ==========
    first_name AS customer_first_name,
    -- Note: last_name_hash NOT exposed to avoid confusion
    tags AS customer_tags,
    created_at AS customer_created_at,
    orders_count AS customer_order_count_shopify,
    verified_email AS customer_email_verified,
    accepts_marketing AS customer_accepts_marketing,

    -- Marketing consent dates
    JSON_EXTRACT_SCALAR(email_marketing_consent, '$.consent_updated_at') AS email_consent_date,
    JSON_EXTRACT_SCALAR(sms_marketing_consent, '$.consent_updated_at') AS sms_consent_date,
    JSON_EXTRACT_SCALAR(email_marketing_consent, '$.state') AS email_consent_status,
    JSON_EXTRACT_SCALAR(sms_marketing_consent, '$.state') AS sms_consent_status,

    -- ========== TARGETS ==========
    CAST(total_spent AS FLOAT64) AS customer_lifetime_value_shopify,

    -- ========== METADATA ==========
    _airbyte_extracted_at AS customer_last_sync_at

  FROM `hulken.ads_data.shopify_live_customers_clean`
),

items_aggregated AS (
  SELECT
    -- Extract order_id from gid://shopify/Order/4135050674342
    CAST(REGEXP_EXTRACT(order_id, r'(\d+)') AS INT64) AS order_id_numeric,

    -- Aggregated metrics
    COUNT(*) AS items_count,
    SUM(CAST(quantity AS INT64)) AS total_quantity,
    STRING_AGG(DISTINCT sku, ', ') AS skus,
    STRING_AGG(DISTINCT title, ', ') AS product_titles,
    SUM(CAST(JSON_EXTRACT_SCALAR(originalTotal, '$.amount') AS FLOAT64)) AS items_total_original,

  FROM `hulken.ads_data.shopify_live_items`
  WHERE order_id IS NOT NULL
  GROUP BY order_id_numeric
),

transactions_aggregated AS (
  SELECT
    order_id AS order_id_numeric,

    COUNT(*) AS transaction_count,
    STRING_AGG(DISTINCT gateway, ', ') AS payment_gateways,
    STRING_AGG(DISTINCT status, ', ') AS transaction_statuses,
    SUM(CAST(amount AS FLOAT64)) AS transactions_total_amount,
    MIN(created_at) AS first_transaction_at,
    MAX(created_at) AS last_transaction_at,

  FROM `hulken.ads_data.shopify_live_transactions`
  WHERE order_id IS NOT NULL
  GROUP BY order_id
),

utm_attribution AS (
  SELECT
    CAST(REGEXP_EXTRACT(order_id, r'(\d+)') AS INT64) AS order_id_numeric,

    -- ========== GROUPBY FEATURES ==========
    sales_channel,
    sales_channel_name,
    attribution_status,

    -- ========== FEATURES ==========
    first_utm_source,
    first_utm_medium,
    first_utm_campaign,
    first_utm_content,
    first_utm_term,
    first_landing_page,
    first_referrer_url,
    first_visit_at,

    last_utm_source,
    last_utm_medium,
    last_utm_campaign,
    last_landing_page,
    last_visit_at,

    customer_order_index,
    days_to_conversion,

    -- ========== METADATA ==========
    extracted_at AS utm_extracted_at

  FROM `hulken.ads_data.shopify_utm`
  WHERE order_id IS NOT NULL
),

refunds_aggregated AS (
  SELECT
    order_id AS order_id_numeric,

    COUNT(*) AS refund_count,
    SUM(CAST(JSON_EXTRACT_SCALAR(note, r'\$([0-9.]+)') AS FLOAT64)) AS refunds_total_amount,
    MAX(created_at) AS last_refund_at,

  FROM `hulken.ads_data.shopify_live_order_refunds`
  WHERE order_id IS NOT NULL
  GROUP BY order_id
)

-- ========== FINAL MERGE ==========
SELECT
  o.*,

  -- Customer data
  c.customer_id,
  c.customer_first_name,
  c.customer_tags,
  c.customer_created_at,
  c.customer_order_count_shopify,
  c.customer_email_verified,
  c.customer_accepts_marketing,
  c.email_consent_date,
  c.sms_consent_date,
  c.email_consent_status,
  c.sms_consent_status,
  c.customer_lifetime_value_shopify,
  c.customer_state,

  -- Items data (override placeholder)
  COALESCE(i.items_count, 0) AS items_count,
  i.total_quantity,
  i.skus,
  i.product_titles,
  i.items_total_original,

  -- Transactions data
  t.transaction_count,
  t.payment_gateways,
  t.transaction_statuses,
  t.transactions_total_amount,
  t.first_transaction_at,
  t.last_transaction_at,

  -- UTM attribution
  u.sales_channel,
  u.sales_channel_name,
  u.attribution_status,
  u.first_utm_source,
  u.first_utm_medium,
  u.first_utm_campaign,
  u.first_utm_content,
  u.first_utm_term,
  u.first_landing_page,
  u.first_referrer_url,
  u.first_visit_at,
  u.last_utm_source,
  u.last_utm_medium,
  u.last_utm_campaign,
  u.last_landing_page,
  u.last_visit_at,
  u.customer_order_index,
  u.days_to_conversion,

  -- Refunds data
  r.refund_count,
  r.refunds_total_amount,
  r.last_refund_at,

  -- ========== CALCULATED METRICS ==========
  CASE
    WHEN o.order_cancelled_at IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_cancelled,

  CASE
    WHEN r.refund_count > 0 THEN TRUE
    ELSE FALSE
  END AS has_refund,

  -- Net order value (after discounts and refunds)
  o.order_value - COALESCE(o.order_discounts, 0) - COALESCE(r.refunds_total_amount, 0) AS order_net_value,

  -- Attribution channel
  CASE
    WHEN u.first_utm_source IS NOT NULL THEN u.first_utm_source
    WHEN o.source_name IS NOT NULL THEN o.source_name
    ELSE 'direct'
  END AS attribution_channel

FROM orders_base o
LEFT JOIN customers_enhanced c
  ON o.order_email_hash = c.customer_email_hash
LEFT JOIN items_aggregated i
  ON o.order_id_numeric = i.order_id_numeric
LEFT JOIN transactions_aggregated t
  ON o.order_id_numeric = t.order_id_numeric
LEFT JOIN utm_attribution u
  ON o.order_id_numeric = u.order_id_numeric
LEFT JOIN refunds_aggregated r
  ON o.order_id_numeric = r.order_id_numeric;

-- ============================================================
-- Verify shopify_unified
-- ============================================================
SELECT
  'shopify_unified' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT order_id) AS unique_orders,
  COUNT(DISTINCT customer_id) AS unique_customers,
  SUM(order_value) AS total_gmv,
  SUM(order_net_value) AS total_net_gmv
FROM `hulken.ads_data.shopify_unified`;


-- ============================================================
-- PART 2: FACEBOOK UNIFIED
-- ============================================================
-- Facebook Ads insights with calculated metrics

CREATE OR REPLACE TABLE `hulken.ads_data.facebook_unified` AS

SELECT
  -- ========== INDEXES ==========
  CONCAT(account_id, '_', date_start, '_', COALESCE(campaign_id, 'unknown')) AS fb_row_id,
  account_id AS fb_account_id,
  campaign_id AS fb_campaign_id,
  adset_id AS fb_adset_id,
  ad_id AS fb_ad_id,
  DATE(date_start) AS date,

  -- ========== GROUPBY FEATURES ==========
  account_name AS fb_account_name,
  campaign_name AS fb_campaign_name,
  adset_name AS fb_adset_name,
  ad_name AS fb_ad_name,

  -- ========== FEATURES ==========
  date_start,
  date_stop,

  -- ========== TARGETS (Metrics) ==========
  CAST(spend AS FLOAT64) AS fb_spend,
  CAST(impressions AS INT64) AS fb_impressions,
  CAST(clicks AS INT64) AS fb_clicks,
  CAST(reach AS INT64) AS fb_reach,

  -- ========== CALCULATED METRICS ==========
  SAFE_DIVIDE(CAST(clicks AS FLOAT64), CAST(impressions AS INT64)) * 100 AS fb_ctr_percent,
  SAFE_DIVIDE(CAST(spend AS FLOAT64), CAST(clicks AS INT64)) AS fb_cpc,
  SAFE_DIVIDE(CAST(spend AS FLOAT64), CAST(impressions AS INT64)) * 1000 AS fb_cpm,

  -- TODO: Parse actions JSON for conversions
  -- For now, keep as string
  actions AS fb_actions_json,

  -- ========== METADATA ==========
  _airbyte_extracted_at AS fb_last_sync_at

FROM `hulken.ads_data.facebook_insights`
WHERE date_start IS NOT NULL;

-- Verify
SELECT 'facebook_unified' AS table_name, COUNT(*) AS row_count, SUM(fb_spend) AS total_spend
FROM `hulken.ads_data.facebook_unified`;


-- ============================================================
-- PART 3: TIKTOK UNIFIED
-- ============================================================
-- TikTok Ads daily reports with calculated metrics

CREATE OR REPLACE TABLE `hulken.ads_data.tiktok_unified` AS

SELECT
  -- ========== INDEXES ==========
  CONCAT(CAST(report_date AS STRING), '_', COALESCE(CAST(campaign_id AS STRING), 'unknown')) AS tt_row_id,
  report_date AS date,
  campaign_id AS tt_campaign_id,
  adgroup_id AS tt_adgroup_id,
  ad_id AS tt_ad_id,

  -- ========== GROUPBY FEATURES ==========
  campaign_name AS tt_campaign_name,
  adgroup_name AS tt_adgroup_name,
  ad_name AS tt_ad_name,

  -- ========== TARGETS (Metrics) ==========
  spend AS tt_spend,
  impressions AS tt_impressions,
  clicks AS tt_clicks,
  conversions AS tt_conversions,

  -- ========== CALCULATED METRICS ==========
  SAFE_DIVIDE(clicks, impressions) * 100 AS tt_ctr_percent,
  SAFE_DIVIDE(spend, clicks) AS tt_cpc,
  SAFE_DIVIDE(spend, impressions) * 1000 AS tt_cpm,
  SAFE_DIVIDE(conversions, clicks) * 100 AS tt_conversion_rate,
  SAFE_DIVIDE(spend, NULLIF(conversions, 0)) AS tt_cpa,

  -- ========== METADATA ==========
  _airbyte_extracted_at AS tt_last_sync_at

FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE report_date IS NOT NULL;

-- Verify
SELECT 'tiktok_unified' AS table_name, COUNT(*) AS row_count, SUM(tt_spend) AS total_spend
FROM `hulken.ads_data.tiktok_unified`;


-- ============================================================
-- PART 4: MARKETING UNIFIED (MASTER TABLE)
-- ============================================================
-- Combines Shopify orders with ad platform attribution

CREATE OR REPLACE TABLE `hulken.ads_data.marketing_unified` AS

WITH daily_ad_spend AS (
  -- Aggregate ad spend by date and source
  SELECT
    date,
    'facebook' AS ad_source,
    SUM(fb_spend) AS spend,
    SUM(fb_impressions) AS impressions,
    SUM(fb_clicks) AS clicks
  FROM `hulken.ads_data.facebook_unified`
  GROUP BY date

  UNION ALL

  SELECT
    date,
    'tiktok' AS ad_source,
    SUM(tt_spend) AS spend,
    SUM(tt_impressions) AS impressions,
    SUM(tt_clicks) AS clicks
  FROM `hulken.ads_data.tiktok_unified`
  GROUP BY date
),

shopify_daily AS (
  SELECT
    order_date AS date,
    attribution_channel,
    first_utm_source,

    COUNT(*) AS orders,
    SUM(order_value) AS revenue,
    SUM(order_net_value) AS net_revenue,
    COUNT(DISTINCT customer_id) AS unique_customers

  FROM `hulken.ads_data.shopify_unified`
  WHERE order_date IS NOT NULL
  GROUP BY order_date, attribution_channel, first_utm_source
)

SELECT
  -- ========== INDEXES ==========
  CONCAT(CAST(COALESCE(s.date, a.date) AS STRING), '_', COALESCE(s.attribution_channel, a.ad_source, 'unknown')) AS row_id,
  COALESCE(s.date, a.date) AS date,

  -- ========== GROUPBY FEATURES ==========
  COALESCE(s.attribution_channel, a.ad_source, 'organic') AS channel,
  s.first_utm_source AS utm_source,

  -- ========== TARGETS (Shopify metrics) ==========
  COALESCE(s.orders, 0) AS orders,
  COALESCE(s.revenue, 0) AS revenue,
  COALESCE(s.net_revenue, 0) AS net_revenue,
  COALESCE(s.unique_customers, 0) AS unique_customers,

  -- ========== TARGETS (Ad platform metrics) ==========
  COALESCE(a.spend, 0) AS ad_spend,
  COALESCE(a.impressions, 0) AS ad_impressions,
  COALESCE(a.clicks, 0) AS ad_clicks,

  -- ========== CALCULATED METRICS ==========
  SAFE_DIVIDE(COALESCE(s.revenue, 0), NULLIF(COALESCE(a.spend, 0), 0)) AS roas,
  SAFE_DIVIDE(COALESCE(a.spend, 0), NULLIF(COALESCE(s.orders, 0), 0)) AS cpa,
  SAFE_DIVIDE(COALESCE(s.revenue, 0), NULLIF(COALESCE(s.orders, 0), 0)) AS avg_order_value,
  SAFE_DIVIDE(COALESCE(a.clicks, 0), NULLIF(COALESCE(a.impressions, 0), 0)) * 100 AS ctr_percent,
  SAFE_DIVIDE(COALESCE(s.orders, 0), NULLIF(COALESCE(a.clicks, 0), 0)) * 100 AS conversion_rate

FROM shopify_daily s
FULL OUTER JOIN daily_ad_spend a
  ON s.date = a.date
  AND LOWER(s.attribution_channel) = LOWER(a.ad_source);

-- Verify
SELECT
  'marketing_unified' AS table_name,
  COUNT(*) AS row_count,
  SUM(revenue) AS total_revenue,
  SUM(ad_spend) AS total_spend,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS overall_roas
FROM `hulken.ads_data.marketing_unified`;


-- ============================================================
-- FINAL SUMMARY
-- ============================================================
SELECT
  table_name,
  row_count,
  ROUND(size_bytes / 1024 / 1024, 2) AS size_mb
FROM `hulken.ads_data.__TABLES__`
WHERE table_name IN ('shopify_unified', 'facebook_unified', 'tiktok_unified', 'marketing_unified')
ORDER BY table_name;
