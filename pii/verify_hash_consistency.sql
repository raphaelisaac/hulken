-- ============================================================
-- VERIFY HASH CONSISTENCY ACROSS ALL TABLES
-- ============================================================
-- This script verifies that:
-- 1. All tables have email_hash column
-- 2. All emails have been hashed
-- 3. Same email produces same hash across tables
-- 4. No orphaned hashes (hash without corresponding email)
-- ============================================================


-- ============================================================
-- CHECK 1: Column Existence
-- ============================================================

SELECT
  table_name,
  column_name,
  data_type
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('shopify_orders', 'shopify_live_orders', 'shopify_live_customers')
  AND column_name = 'email_hash'
ORDER BY table_name;

-- Expected: 3 rows (one for each table)


-- ============================================================
-- CHECK 2: Hash Coverage Statistics
-- ============================================================

SELECT
  'shopify_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(customer_email IS NOT NULL) as rows_with_email,
  COUNTIF(customer_email IS NOT NULL AND email_hash IS NULL) as email_without_hash,
  COUNTIF(customer_email IS NULL AND email_hash IS NOT NULL) as hash_without_email,
  ROUND(100.0 * COUNTIF(email_hash IS NOT NULL) / NULLIF(COUNTIF(customer_email IS NOT NULL), 0), 2) as pct_hashed
FROM `hulken.ads_data.shopify_orders`

UNION ALL

SELECT
  'shopify_live_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as email_without_hash,
  COUNTIF(email IS NULL AND email_hash IS NOT NULL) as hash_without_email,
  ROUND(100.0 * COUNTIF(email_hash IS NOT NULL) / NULLIF(COUNTIF(email IS NOT NULL), 0), 2) as pct_hashed
FROM `hulken.ads_data.shopify_live_orders`

UNION ALL

SELECT
  'shopify_live_customers' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as email_without_hash,
  COUNTIF(email IS NULL AND email_hash IS NOT NULL) as hash_without_email,
  ROUND(100.0 * COUNTIF(email_hash IS NOT NULL) / NULLIF(COUNTIF(email IS NOT NULL), 0), 2) as pct_hashed
FROM `hulken.ads_data.shopify_live_customers`;


-- ============================================================
-- CHECK 3: Hash Function Consistency Test
-- ============================================================
-- Verify that the hash function produces consistent results

WITH test_emails AS (
  SELECT 'test@example.com' as email
  UNION ALL SELECT 'TEST@EXAMPLE.COM'
  UNION ALL SELECT ' test@example.com '
  UNION ALL SELECT 'another@test.org'
)
SELECT
  email as original_email,
  LOWER(TRIM(email)) as normalized_email,
  TO_HEX(SHA256(LOWER(TRIM(email)))) as hash
FROM test_emails;

-- Expected: First 3 emails should have SAME hash (after normalization)


-- ============================================================
-- CHECK 4: Cross-Table Hash Matching
-- ============================================================
-- Find customers that exist in multiple tables and verify their hashes match

WITH customer_hashes AS (
  SELECT DISTINCT
    c.email_hash,
    c.email as customer_email,
    TO_HEX(SHA256(LOWER(TRIM(c.email)))) as customer_computed_hash
  FROM `hulken.ads_data.shopify_live_customers` c
  WHERE c.email IS NOT NULL
),
order_hashes AS (
  SELECT DISTINCT
    o.email_hash,
    o.email as order_email,
    TO_HEX(SHA256(LOWER(TRIM(o.email)))) as order_computed_hash
  FROM `hulken.ads_data.shopify_live_orders` o
  WHERE o.email IS NOT NULL
)
SELECT
  ch.customer_email,
  ch.email_hash as customer_hash,
  oh.email_hash as order_hash,
  ch.customer_computed_hash,
  oh.order_computed_hash,
  CASE
    WHEN ch.email_hash = oh.email_hash THEN 'MATCH'
    WHEN ch.email_hash IS NULL OR oh.email_hash IS NULL THEN 'MISSING HASH'
    ELSE 'MISMATCH'
  END as status
FROM customer_hashes ch
INNER JOIN order_hashes oh
  ON LOWER(TRIM(ch.customer_email)) = LOWER(TRIM(oh.order_email))
LIMIT 20;


-- ============================================================
-- CHECK 5: Find Unhashed Emails (if any)
-- ============================================================

-- Unhashed emails in shopify_live_orders
SELECT 'shopify_live_orders' as table_name, email, created_at
FROM `hulken.ads_data.shopify_live_orders`
WHERE email IS NOT NULL AND (email_hash IS NULL OR email_hash = '')
LIMIT 10;

-- Unhashed emails in shopify_live_customers
SELECT 'shopify_live_customers' as table_name, email, created_at
FROM `hulken.ads_data.shopify_live_customers`
WHERE email IS NOT NULL AND (email_hash IS NULL OR email_hash = '')
LIMIT 10;


-- ============================================================
-- CHECK 6: Unique Hash Count vs Unique Email Count
-- ============================================================
-- These should match if hashing is consistent

SELECT
  'shopify_live_orders' as table_name,
  COUNT(DISTINCT LOWER(TRIM(email))) as unique_emails,
  COUNT(DISTINCT email_hash) as unique_hashes
FROM `hulken.ads_data.shopify_live_orders`
WHERE email IS NOT NULL

UNION ALL

SELECT
  'shopify_live_customers' as table_name,
  COUNT(DISTINCT LOWER(TRIM(email))) as unique_emails,
  COUNT(DISTINCT email_hash) as unique_hashes
FROM `hulken.ads_data.shopify_live_customers`
WHERE email IS NOT NULL;


-- ============================================================
-- SUMMARY
-- ============================================================
-- If all checks pass:
-- - All tables have email_hash column
-- - pct_hashed = 100% for rows with email
-- - email_without_hash = 0
-- - Cross-table status = MATCH for all
-- - unique_emails = unique_hashes
-- ============================================================
