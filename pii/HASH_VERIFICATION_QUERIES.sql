-- =============================================================================
-- HASH VERIFICATION QUERIES FOR PII DATA COMPLIANCE
-- =============================================================================
-- Purpose: Verify email hash consistency across all BigQuery tables
-- Standard Hash Function: TO_HEX(SHA256(LOWER(TRIM(email))))
-- Created: 2026-02-04
-- =============================================================================

-- =============================================================================
-- SECTION 1: HASH FUNCTION VERIFICATION
-- =============================================================================

-- 1.1 Test that hash function normalizes case and whitespace
-- Expected result: Both should produce the same hash
SELECT
  'Test 1: Case and Whitespace Normalization' as test_name,
  'Test@Example.com ' as input_with_case_and_space,
  TO_HEX(SHA256(LOWER(TRIM('Test@Example.com ')))) as hash_from_input,
  'test@example.com' as normalized_input,
  TO_HEX(SHA256(LOWER(TRIM('test@example.com')))) as hash_from_normalized,
  CASE
    WHEN TO_HEX(SHA256(LOWER(TRIM('Test@Example.com ')))) = TO_HEX(SHA256(LOWER(TRIM('test@example.com'))))
    THEN 'PASS - Hashes match'
    ELSE 'FAIL - Hashes differ'
  END as test_result;

-- 1.2 Expected hash format demonstration
SELECT
  'Test 2: Expected Hash Format' as test_name,
  'test@example.com' as email,
  TO_HEX(SHA256(LOWER(TRIM('test@example.com')))) as expected_hash_format;
  -- Expected output: 973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b


-- =============================================================================
-- SECTION 2: CROSS-TABLE HASH CONSISTENCY VERIFICATION
-- =============================================================================

-- 2.1 Verify hash consistency between shopify_live_orders and shopify_live_customers
-- Check that same email produces identical hash in both tables
WITH orders_emails AS (
  SELECT
    LOWER(TRIM(email)) as normalized_email,
    TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_orders`
  WHERE email IS NOT NULL
  GROUP BY email
),
customers_emails AS (
  SELECT
    LOWER(TRIM(email)) as normalized_email,
    TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_customers`
  WHERE email IS NOT NULL
  GROUP BY email
)
SELECT
  'Test 3: Cross-Table Hash Consistency' as test_name,
  COUNT(*) as total_common_emails,
  SUM(CASE WHEN o.email_hash = c.email_hash THEN 1 ELSE 0 END) as matching_hashes,
  SUM(CASE WHEN o.email_hash != c.email_hash THEN 1 ELSE 0 END) as mismatched_hashes,
  CASE
    WHEN SUM(CASE WHEN o.email_hash != c.email_hash THEN 1 ELSE 0 END) = 0
    THEN 'PASS - All hashes consistent'
    ELSE 'FAIL - Hash mismatches found'
  END as test_result
FROM orders_emails o
INNER JOIN customers_emails c ON o.normalized_email = c.normalized_email;


-- 2.2 Sample hash comparison showing matches
SELECT
  o.email,
  o.email_hash as order_hash,
  c.email_hash as customer_hash,
  CASE WHEN o.email_hash = c.email_hash THEN 'MATCH' ELSE 'MISMATCH' END as status
FROM (
  SELECT email, TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_orders`
  WHERE email IS NOT NULL
  GROUP BY email
) o
INNER JOIN (
  SELECT email, TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_customers`
  WHERE email IS NOT NULL
  GROUP BY email
) c ON LOWER(TRIM(o.email)) = LOWER(TRIM(c.email))
LIMIT 20;


-- =============================================================================
-- SECTION 3: CROSS-TABLE JOIN TESTS
-- =============================================================================

-- 3.1 Count email_hash overlap between tables
WITH orders_emails AS (
  SELECT DISTINCT TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_orders`
  WHERE email IS NOT NULL
),
customers_emails AS (
  SELECT DISTINCT TO_HEX(SHA256(LOWER(TRIM(email)))) as email_hash
  FROM `hulken.ads_data.shopify_live_customers`
  WHERE email IS NOT NULL
),
overlap AS (
  SELECT o.email_hash
  FROM orders_emails o
  INNER JOIN customers_emails c ON o.email_hash = c.email_hash
)
SELECT
  'Test 4: Email Hash Overlap Statistics' as test_name,
  (SELECT COUNT(*) FROM orders_emails) as unique_orders_emails,
  (SELECT COUNT(*) FROM customers_emails) as unique_customers_emails,
  (SELECT COUNT(*) FROM overlap) as matching_emails_across_tables;


-- 3.2 Cross-table join test: Orders with Customer data via email_hash
-- Demonstrates that joins work correctly using calculated hashes
SELECT
  o.name as order_name,
  o.total_price,
  c.orders_count,
  c.total_spent,
  TO_HEX(SHA256(LOWER(TRIM(o.email)))) as email_hash
FROM `hulken.ads_data.shopify_live_orders` o
JOIN `hulken.ads_data.shopify_live_customers` c
  ON TO_HEX(SHA256(LOWER(TRIM(o.email)))) = TO_HEX(SHA256(LOWER(TRIM(c.email))))
WHERE o.email IS NOT NULL
LIMIT 10;


-- 3.3 Customer Lifetime Value analysis via email_hash join
SELECT
  TO_HEX(SHA256(LOWER(TRIM(o.email)))) as email_hash,
  COUNT(DISTINCT o.id) as orders,
  SUM(o.total_price) as order_total,
  MAX(c.total_spent) as customer_ltv,
  MAX(c.orders_count) as customer_orders_count
FROM `hulken.ads_data.shopify_live_orders` o
LEFT JOIN `hulken.ads_data.shopify_live_customers` c
  ON TO_HEX(SHA256(LOWER(TRIM(o.email)))) = TO_HEX(SHA256(LOWER(TRIM(c.email))))
WHERE o.email IS NOT NULL
GROUP BY 1
ORDER BY orders DESC
LIMIT 10;


-- =============================================================================
-- SECTION 4: PII AUDIT QUERIES
-- =============================================================================

-- 4.1 Count records with email still present (raw PII exposure)
SELECT
  'shopify_live_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  ROUND(COUNTIF(email IS NOT NULL) * 100.0 / COUNT(*), 2) as pii_exposure_pct
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  ROUND(COUNTIF(email IS NOT NULL) * 100.0 / COUNT(*), 2) as pii_exposure_pct
FROM `hulken.ads_data.shopify_live_customers`;


-- 4.2 Full PII audit across Shopify tables
SELECT
  'shopify_live_orders' as table_name,
  'email' as pii_field,
  COUNTIF(email IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT
  'shopify_live_orders' as table_name,
  'phone' as pii_field,
  COUNTIF(phone IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  'email' as pii_field,
  COUNTIF(email IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_customers`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  'phone' as pii_field,
  COUNTIF(phone IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_customers`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  'first_name' as pii_field,
  COUNTIF(first_name IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_customers`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  'last_name' as pii_field,
  COUNTIF(last_name IS NOT NULL) as non_null_count
FROM `hulken.ads_data.shopify_live_customers`;


-- =============================================================================
-- SECTION 5: POST-HASHING VALIDATION QUERIES
-- =============================================================================
-- Run these after implementing email hashing to verify success

-- 5.1 Verify email_hash column exists and is populated
-- (Modify table name based on your implementation)
/*
SELECT
  'Post-Hash Validation' as test_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL) as rows_with_raw_email,
  CASE
    WHEN COUNTIF(email IS NOT NULL) = 0 AND COUNTIF(email_hash IS NOT NULL) > 0
    THEN 'PASS - PII removed, hashes present'
    ELSE 'FAIL - PII still present or hashes missing'
  END as status
FROM `hulken.ads_data.shopify_live_orders`;
*/


-- 5.2 Verify join capability with stored email_hash
-- (For use after email_hash column is added to tables)
/*
SELECT
  o.email_hash,
  COUNT(DISTINCT o.id) as orders,
  MAX(c.total_spent) as customer_ltv
FROM `hulken.ads_data.shopify_live_orders` o
LEFT JOIN `hulken.ads_data.shopify_live_customers` c
  ON o.email_hash = c.email_hash
WHERE o.email_hash IS NOT NULL
GROUP BY 1
LIMIT 10;
*/


-- =============================================================================
-- SECTION 6: REFERENCE INFORMATION
-- =============================================================================

-- Tables with email_hash already implemented:
-- - shopify_orders (has email_hash column, no raw email)

-- Tables requiring email hashing implementation:
-- - shopify_live_orders (has raw email, no email_hash)
-- - shopify_live_customers (has raw email, no email_hash)

-- Standard Hash Function (MUST be used everywhere):
-- TO_HEX(SHA256(LOWER(TRIM(email))))

-- =============================================================================
-- END OF HASH VERIFICATION QUERIES
-- =============================================================================
