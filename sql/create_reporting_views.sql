-- ============================================================
-- REPORTING VIEWS FOR LOOKER STUDIO
-- ============================================================
-- Crée des vues pré-agrégées pour faciliter le reporting
-- et accélérer les dashboards Looker Studio
--
-- Created: 2026-02-15
-- ============================================================

-- ============================================================
-- 1. SHOPIFY DAILY METRICS
-- ============================================================
-- Agrégation quotidienne de toutes les métriques Shopify

CREATE OR REPLACE VIEW `hulken.ads_data.shopify_daily_metrics` AS

SELECT
  order_date AS date,

  -- ========== ORDERS & REVENUE ==========
  COUNT(DISTINCT order_id) AS orders,
  SUM(order_value) AS gross_revenue,
  SUM(order_net_value) AS net_revenue,
  AVG(order_value) AS aov,
  SUM(order_discounts) AS total_discounts,
  SUM(order_tax) AS total_tax,

  -- ========== CUSTOMERS ==========
  COUNT(DISTINCT customer_id) AS unique_customers,
  COUNT(DISTINCT CASE WHEN customer_order_count_shopify > 1 THEN customer_id END) AS returning_customers,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN customer_order_count_shopify > 1 THEN customer_id END),
    COUNT(DISTINCT customer_id)
  ) * 100 AS returning_customer_pct,

  -- ========== ITEMS ==========
  SUM(items_count) AS total_items,
  SUM(total_quantity) AS total_units,
  AVG(items_count) AS avg_items_per_order,

  -- ========== ATTRIBUTION ==========
  COUNT(DISTINCT CASE WHEN first_utm_source = 'facebook' THEN order_id END) AS facebook_orders,
  COUNT(DISTINCT CASE WHEN first_utm_source = 'google' THEN order_id END) AS google_orders,
  COUNT(DISTINCT CASE WHEN first_utm_source = 'tiktok' THEN order_id END) AS tiktok_orders,
  COUNT(DISTINCT CASE WHEN first_utm_source IS NULL THEN order_id END) AS direct_orders,

  -- ========== ORDER STATUS ==========
  COUNT(DISTINCT CASE WHEN is_cancelled = TRUE THEN order_id END) AS cancelled_orders,
  COUNT(DISTINCT CASE WHEN has_refund = TRUE THEN order_id END) AS refunded_orders,
  SUM(CASE WHEN has_refund = TRUE THEN refunds_total_amount ELSE 0 END) AS total_refund_amount,

  -- ========== TRANSACTIONS ==========
  AVG(transaction_count) AS avg_transactions_per_order,
  SUM(transactions_total_amount) AS total_transaction_amount

FROM `hulken.ads_data.shopify_unified`
WHERE order_date IS NOT NULL
GROUP BY order_date;


-- ============================================================
-- 2. MARKETING CHANNEL PERFORMANCE (Monthly)
-- ============================================================
-- Vue mensuelle des performances par canal avec KPIs complets

CREATE OR REPLACE VIEW `hulken.ads_data.marketing_monthly_performance` AS

SELECT
  DATE_TRUNC(date, MONTH) AS month,
  channel,

  -- ========== SPEND ==========
  SUM(ad_spend) AS total_spend,
  AVG(ad_spend) AS avg_daily_spend,

  -- ========== REVENUE ==========
  SUM(revenue) AS total_revenue,
  SUM(net_revenue) AS total_net_revenue,
  AVG(revenue) AS avg_daily_revenue,

  -- ========== ORDERS ==========
  SUM(orders) AS total_orders,
  AVG(orders) AS avg_daily_orders,

  -- ========== CUSTOMERS ==========
  SUM(unique_customers) AS total_customers,

  -- ========== AD METRICS ==========
  SUM(ad_impressions) AS total_impressions,
  SUM(ad_clicks) AS total_clicks,
  AVG(ctr_percent) AS avg_ctr,

  -- ========== EFFICIENCY METRICS ==========
  SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas,
  SAFE_DIVIDE(SUM(ad_spend), SUM(orders)) AS cpa,
  SAFE_DIVIDE(SUM(revenue), SUM(orders)) AS aov,
  SAFE_DIVIDE(SUM(net_revenue), SUM(ad_spend)) AS mer,
  SAFE_DIVIDE(SUM(ad_spend), SUM(revenue)) * 100 AS marketing_pct_of_revenue,

  -- ========== CONTRIBUTION ==========
  SUM(revenue) - SUM(ad_spend) AS contribution_margin,
  SAFE_DIVIDE(SUM(revenue) - SUM(ad_spend), SUM(revenue)) * 100 AS contribution_margin_pct

FROM `hulken.ads_data.marketing_unified`
WHERE date IS NOT NULL
GROUP BY month, channel;


-- ============================================================
-- 3. PRODUCT PERFORMANCE VIEW
-- ============================================================
-- Top produits avec métriques de vente

CREATE OR REPLACE VIEW `hulken.ads_data.product_performance` AS

WITH product_sales AS (
  SELECT
    product_titles,
    order_date,

    COUNT(DISTINCT order_id) AS orders,
    SUM(total_quantity) AS units_sold,
    SUM(items_total_original) AS gross_revenue,
    SUM(items_total_original - COALESCE(order_discounts, 0)) AS net_revenue,
    AVG(SAFE_DIVIDE(items_total_original, total_quantity)) AS avg_price

  FROM `hulken.ads_data.shopify_unified`
  WHERE product_titles IS NOT NULL
    AND product_titles != ''
  GROUP BY product_titles, order_date
)

SELECT
  DATE_TRUNC(order_date, MONTH) AS month,
  product_titles AS product_name,

  SUM(orders) AS total_orders,
  SUM(units_sold) AS total_units,
  SUM(gross_revenue) AS gross_revenue,
  SUM(net_revenue) AS net_revenue,
  AVG(avg_price) AS avg_price,

  SAFE_DIVIDE(SUM(net_revenue), SUM(units_sold)) AS revenue_per_unit

FROM product_sales
GROUP BY month, product_titles;


-- ============================================================
-- 4. EXECUTIVE SUMMARY VIEW
-- ============================================================
-- KPIs mensuels avec comparaison YoY

CREATE OR REPLACE VIEW `hulken.ads_data.executive_summary_monthly` AS

WITH monthly_metrics AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,

    -- Revenue metrics
    SUM(revenue) AS gross_revenue,
    SUM(net_revenue) AS net_revenue,

    -- Spend metrics
    SUM(ad_spend) AS marketing_spend,

    -- Volume metrics
    SUM(orders) AS orders,
    SUM(unique_customers) AS customers,

    -- Efficiency metrics
    AVG(avg_order_value) AS aov,
    SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas,
    SAFE_DIVIDE(SUM(ad_spend), SUM(orders)) AS cpa,

    -- Contribution
    SUM(net_revenue) - SUM(ad_spend) AS pre_marketing_contribution,
    SAFE_DIVIDE(SUM(ad_spend), SUM(net_revenue)) * 100 AS marketing_pct

  FROM `hulken.ads_data.marketing_unified`
  GROUP BY month
),

yoy_comparison AS (
  SELECT
    m1.month,

    -- Current month
    m1.gross_revenue,
    m1.net_revenue,
    m1.marketing_spend,
    m1.orders,
    m1.customers,
    m1.aov,
    m1.roas,
    m1.cpa,
    m1.pre_marketing_contribution,
    m1.marketing_pct,

    -- Last year same month
    m2.gross_revenue AS ly_gross_revenue,
    m2.net_revenue AS ly_net_revenue,
    m2.marketing_spend AS ly_marketing_spend,
    m2.orders AS ly_orders,
    m2.customers AS ly_customers,

    -- YoY % change
    SAFE_DIVIDE(m1.gross_revenue - m2.gross_revenue, m2.gross_revenue) * 100 AS gross_revenue_yoy,
    SAFE_DIVIDE(m1.net_revenue - m2.net_revenue, m2.net_revenue) * 100 AS net_revenue_yoy,
    SAFE_DIVIDE(m1.marketing_spend - m2.marketing_spend, m2.marketing_spend) * 100 AS marketing_spend_yoy,
    SAFE_DIVIDE(m1.orders - m2.orders, m2.orders) * 100 AS orders_yoy,
    SAFE_DIVIDE(m1.roas - m2.roas, m2.roas) * 100 AS roas_yoy

  FROM monthly_metrics m1
  LEFT JOIN monthly_metrics m2
    ON m1.month = DATE_ADD(m2.month, INTERVAL 1 YEAR)
)

SELECT * FROM yoy_comparison;


-- ============================================================
-- 5. CHANNEL MIX VIEW
-- ============================================================
-- Distribution du spend et performance par canal

CREATE OR REPLACE VIEW `hulken.ads_data.channel_mix` AS

WITH channel_totals AS (
  SELECT
    channel,
    SUM(ad_spend) AS total_spend,
    SUM(revenue) AS total_revenue,
    SUM(orders) AS total_orders,
    SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas
  FROM `hulken.ads_data.marketing_unified`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY channel
),

total_all_channels AS (
  SELECT
    SUM(total_spend) AS grand_total_spend
  FROM channel_totals
)

SELECT
  c.channel,
  c.total_spend,
  c.total_revenue,
  c.total_orders,
  c.roas,
  SAFE_DIVIDE(c.total_spend, t.grand_total_spend) * 100 AS spend_share_pct,
  SAFE_DIVIDE(c.total_revenue, SUM(c.total_revenue) OVER ()) * 100 AS revenue_share_pct
FROM channel_totals c
CROSS JOIN total_all_channels t
ORDER BY total_spend DESC;


-- ============================================================
-- VERIFY ALL VIEWS
-- ============================================================

SELECT 'shopify_daily_metrics' AS view_name, COUNT(*) AS row_count
FROM `hulken.ads_data.shopify_daily_metrics`

UNION ALL

SELECT 'marketing_monthly_performance', COUNT(*)
FROM `hulken.ads_data.marketing_monthly_performance`

UNION ALL

SELECT 'product_performance', COUNT(*)
FROM `hulken.ads_data.product_performance`

UNION ALL

SELECT 'executive_summary_monthly', COUNT(*)
FROM `hulken.ads_data.executive_summary_monthly`

UNION ALL

SELECT 'channel_mix', COUNT(*)
FROM `hulken.ads_data.channel_mix`

ORDER BY view_name;
