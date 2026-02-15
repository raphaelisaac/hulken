-- ============================================================
-- UPDATE UNIFIED TABLES TO USE PII HASH REFERENCE
-- ============================================================
-- Updates unified tables to use consistent PII hashing via pii_hash_reference
--
-- IMPORTANT: NULL values are PRESERVED (not hashed)
--   - pii_hash_reference contains only non-NULL email hashes
--   - LEFT JOIN ensures NULL emails stay NULL
--   - Result: Same email = same hash everywhere, NULL stays NULL
--
-- Created: 2026-02-15
-- ============================================================

-- ============================================================
-- STEP 1: Verify pii_hash_reference table exists
-- ============================================================
-- Run this first to check if reference table is ready
SELECT
  COUNT(*) AS total_hashes,
  COUNT(DISTINCT email_hash_original) AS unique_emails,
  COUNT(DISTINCT email_hash_consistent) AS unique_consistent_hashes
FROM `hulken.ads_data.pii_hash_reference`;

-- Expected: All three counts should be equal (1:1 mapping)


-- ============================================================
-- STEP 2: Update shopify_unified to use consistent hashing
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.shopify_unified` AS

WITH orders_base AS (
  SELECT
    -- ========== INDEXES ==========
    id AS order_id,
    CAST(REGEXP_EXTRACT(admin_graphql_api_id, r'(\d+)') AS INT64) AS order_id_numeric,
    email_hash AS order_email_hash_original,  -- Keep original for join
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
    TO_JSON_STRING(total_shipping_price_set) AS shipping_info,

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
    email_hash AS customer_email_hash_original,  -- Keep original for join

    -- ========== GROUPBY FEATURES ==========
    state AS customer_state,

    -- ========== FEATURES ==========
    first_name AS customer_first_name,
    tags AS customer_tags,
    created_at AS customer_created_at,
    orders_count AS customer_order_count_shopify,
    CAST(total_spent AS FLOAT64) AS customer_total_spent,
    verified_email AS customer_email_verified,
    accepts_marketing AS customer_accepts_marketing,

    -- ========== TARGETS ==========
    -- These will be calculated from actual orders, not Shopify's aggregates

    -- ========== METADATA ==========
    _airbyte_extracted_at AS customer_last_sync_at

  FROM `hulken.ads_data.shopify_live_customers_clean`
),

-- Line items aggregated
line_items_aggregated AS (
  SELECT
    CAST(REGEXP_EXTRACT(admin_graphql_api_order_id, r'(\d+)') AS INT64) AS order_id_numeric,
    COUNT(*) AS items_count,
    STRING_AGG(title, ', ') AS product_titles,
    STRING_AGG(sku, ', ') AS product_skus,
    SUM(CAST(quantity AS INT64)) AS total_quantity

  FROM `hulken.ads_data.shopify_line_items`
  WHERE admin_graphql_api_order_id IS NOT NULL
  GROUP BY order_id_numeric
),

-- Transactions aggregated
transactions_aggregated AS (
  SELECT
    order_id AS order_id_numeric,
    COUNT(*) AS transaction_count,
    STRING_AGG(DISTINCT kind, ', ') AS transaction_types,
    STRING_AGG(DISTINCT gateway, ', ') AS payment_gateways,
    STRING_AGG(DISTINCT status, ', ') AS transaction_statuses

  FROM `hulken.ads_data.shopify_live_transactions`
  WHERE order_id IS NOT NULL
  GROUP BY order_id
),

-- UTM parameters
utm_params AS (
  SELECT
    CAST(REGEXP_EXTRACT(admin_graphql_api_id, r'(\d+)') AS INT64) AS order_id_numeric,
    landing_site_ref_params AS utm_params_raw,
    REGEXP_EXTRACT(landing_site_ref_params, r'utm_source=([^&]+)') AS utm_source,
    REGEXP_EXTRACT(landing_site_ref_params, r'utm_medium=([^&]+)') AS utm_medium,
    REGEXP_EXTRACT(landing_site_ref_params, r'utm_campaign=([^&]+)') AS utm_campaign,
    REGEXP_EXTRACT(landing_site_ref_params, r'utm_content=([^&]+)') AS utm_content,
    REGEXP_EXTRACT(landing_site_ref_params, r'utm_term=([^&]+)') AS utm_term

  FROM `hulken.ads_data.shopify_utm`
  WHERE admin_graphql_api_id IS NOT NULL
),

-- Refunds aggregated
refunds_aggregated AS (
  SELECT
    order_id AS order_id_numeric,
    COUNT(*) AS refund_count,
    SUM(
      CAST(
        JSON_EXTRACT_SCALAR(
          JSON_EXTRACT_ARRAY(transactions)[SAFE_OFFSET(0)],
          '$.amount'
        ) AS FLOAT64
      )
    ) AS refunds_total_amount,
    MAX(created_at) AS last_refund_at

  FROM `hulken.ads_data.shopify_live_order_refunds`
  WHERE order_id IS NOT NULL
  GROUP BY order_id
)

-- ========== MAIN QUERY WITH CONSISTENT PII HASHING ==========
SELECT
  -- ========== INDEXES ==========
  o.order_id,
  o.order_id_numeric,
  o.order_date,

  -- ========== PII - CONSISTENT HASHING ==========
  -- IMPORTANT: NULL values are preserved (not hashed)
  -- If email_hash_original is NULL, email_hash_consistent will also be NULL (LEFT JOIN)
  COALESCE(pii_orders.email_hash_consistent, o.order_email_hash_original) AS order_email_hash,
  COALESCE(pii_customers.email_hash_consistent, c.customer_email_hash_original) AS customer_email_hash,

  o.order_number_clean,

  -- ========== GROUPBY FEATURES ==========
  o.source_name,
  o.financial_status,
  o.fulfillment_status,
  c.customer_state,

  -- ========== ORDER FEATURES ==========
  o.order_name,
  o.order_created_at,
  o.order_processed_at,
  o.order_cancelled_at,
  o.order_closed_at,
  o.cancel_reason,
  o.order_tags,
  o.order_currency,
  o.landing_site,
  o.referring_site,

  -- ========== CUSTOMER FEATURES ==========
  o.shopify_customer_id,
  c.customer_id,
  c.customer_first_name,
  c.customer_tags,
  c.customer_created_at,
  c.customer_order_count_shopify,
  c.customer_total_spent,
  c.customer_email_verified,
  c.customer_accepts_marketing,

  -- ========== LINE ITEMS ==========
  COALESCE(li.items_count, 0) AS items_count,
  li.product_titles,
  li.product_skus,
  COALESCE(li.total_quantity, 0) AS total_quantity,

  -- ========== TRANSACTIONS ==========
  COALESCE(t.transaction_count, 0) AS transaction_count,
  t.transaction_types,
  t.payment_gateways,
  t.transaction_statuses,

  -- ========== UTM PARAMETERS ==========
  u.utm_params_raw,
  u.utm_source,
  u.utm_medium,
  u.utm_campaign,
  u.utm_content,
  u.utm_term,

  -- ========== REFUNDS ==========
  COALESCE(r.refund_count, 0) AS refund_count,
  COALESCE(r.refunds_total_amount, 0.0) AS refunds_total_amount,
  r.last_refund_at,

  -- ========== TARGETS ==========
  o.order_value,
  o.order_subtotal,
  o.order_discounts,
  o.order_tax,
  o.shipping_info,

  -- Net revenue (after refunds)
  o.order_value - COALESCE(r.refunds_total_amount, 0.0) AS net_revenue,

  -- ========== METADATA ==========
  o.order_last_sync_at,
  c.customer_last_sync_at

FROM orders_base o

-- LEFT JOIN to preserve orders without customers (guest checkouts)
LEFT JOIN customers_enhanced c
  ON o.order_email_hash_original = c.customer_email_hash_original

-- LEFT JOIN pii_hash_reference for orders
-- IMPORTANT: This is a LEFT JOIN, so NULL email_hash stays NULL
LEFT JOIN `hulken.ads_data.pii_hash_reference` pii_orders
  ON o.order_email_hash_original = pii_orders.email_hash_original

-- LEFT JOIN pii_hash_reference for customers
-- IMPORTANT: This is a LEFT JOIN, so NULL email_hash stays NULL
LEFT JOIN `hulken.ads_data.pii_hash_reference` pii_customers
  ON c.customer_email_hash_original = pii_customers.email_hash_original

-- LEFT JOIN to preserve orders without line items
LEFT JOIN line_items_aggregated li
  ON o.order_id_numeric = li.order_id_numeric

-- LEFT JOIN to preserve orders without transactions
LEFT JOIN transactions_aggregated t
  ON o.order_id_numeric = t.order_id_numeric

-- LEFT JOIN to preserve orders without UTM
LEFT JOIN utm_params u
  ON o.order_id_numeric = u.order_id_numeric

-- LEFT JOIN to preserve orders without refunds
LEFT JOIN refunds_aggregated r
  ON o.order_id_numeric = r.order_id_numeric;


-- ============================================================
-- STEP 3: Verify NULL preservation
-- ============================================================
-- Check that NULL emails are still NULL, not hashed

SELECT
  'NULL Preservation Check' AS check_name,
  COUNT(*) AS total_orders,
  COUNTIF(order_email_hash IS NULL) AS null_order_emails,
  COUNTIF(customer_email_hash IS NULL) AS null_customer_emails,
  ROUND(COUNTIF(order_email_hash IS NULL) / COUNT(*) * 100, 2) AS null_order_email_pct,
  ROUND(COUNTIF(customer_email_hash IS NULL) / COUNT(*) * 100, 2) AS null_customer_email_pct
FROM `hulken.ads_data.shopify_unified`;

-- Expected: Some orders should have NULL emails (guest checkouts, etc.)
-- These NULLs should be preserved, not converted to hashes


-- ============================================================
-- STEP 4: Verify consistent hashing
-- ============================================================
-- Check that same email always has same hash

WITH email_hash_mapping AS (
  SELECT DISTINCT
    order_email_hash
  FROM `hulken.ads_data.shopify_unified`
  WHERE order_email_hash IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    customer_email_hash
  FROM `hulken.ads_data.shopify_unified`
  WHERE customer_email_hash IS NOT NULL
)

SELECT
  'Consistent Hashing Check' AS check_name,
  COUNT(*) AS total_unique_hashes,
  COUNT(DISTINCT order_email_hash) AS unique_order_hashes,
  COUNT(DISTINCT customer_email_hash) AS unique_customer_hashes
FROM `hulken.ads_data.shopify_unified`;

-- Expected: Order and customer hashes should be identical when emails match


-- ============================================================
-- STEP 5: Example query showing NULL preservation
-- ============================================================
-- Show orders with NULL emails vs non-NULL emails

SELECT
  CASE
    WHEN order_email_hash IS NULL THEN 'NULL (Guest Checkout)'
    ELSE 'Has Email Hash'
  END AS email_status,
  COUNT(*) AS order_count,
  ROUND(AVG(order_value), 2) AS avg_order_value,
  SUM(order_value) AS total_revenue
FROM `hulken.ads_data.shopify_unified`
GROUP BY email_status
ORDER BY order_count DESC;

-- This shows that NULL emails are preserved and treated separately


-- ============================================================
-- NOTES
-- ============================================================
-- 1. NULL emails are PRESERVED (not hashed)
--    - pii_hash_reference only contains non-NULL emails
--    - LEFT JOIN ensures NULL stays NULL
--    - COALESCE falls back to original if no match in reference
--
-- 2. Consistent hashing for non-NULL emails
--    - Same email in orders and customers → same hash
--    - Same email across different tables → same hash
--
-- 3. Guest checkouts (NULL emails) are valid and preserved
--    - NULL means "no email provided" (guest checkout)
--    - This is semantically different from "email that was hashed"
--
-- 4. To update marketing_unified with consistent hashing:
--    - Run create_unified_tables.sql after this script
--    - marketing_unified will inherit consistent hashes from shopify_unified
--
