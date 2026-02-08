-- ============================================================
-- CROSS-PLATFORM HASH VERIFICATION
-- Ensures identical emails produce identical hashes across all tables
-- Standard: TO_HEX(SHA256(LOWER(TRIM(email))))
-- Run periodically to verify hash integrity
-- ============================================================

-- 1. HASH FORMAT CONSISTENCY
-- All hashes must be exactly 64 chars (SHA256 hex output)
SELECT
  'FORMAT CHECK' AS test,
  source,
  total_hashes,
  correct_64char,
  CASE WHEN wrong_length = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT 'orders_clean' AS source,
    COUNT(*) AS total_hashes,
    COUNTIF(LENGTH(email_hash) = 64) AS correct_64char,
    COUNTIF(LENGTH(email_hash) != 64) AS wrong_length
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE email_hash IS NOT NULL AND email_hash != ''
    AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
  UNION ALL
  SELECT 'customers_clean',
    COUNT(*), COUNTIF(LENGTH(email_hash) = 64), COUNTIF(LENGTH(email_hash) != 64)
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE email_hash IS NOT NULL AND email_hash != ''
    AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
  UNION ALL
  SELECT 'shopify_orders_graphql',
    COUNT(*), COUNTIF(LENGTH(email_hash) = 64), COUNTIF(LENGTH(email_hash) != 64)
  FROM `hulken.ads_data.shopify_orders`
  WHERE email_hash IS NOT NULL AND email_hash != ''
    AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
);

-- 2. CROSS-TABLE MATCH: Orders <-> Customers
-- Same customer should have same hash in both tables
SELECT
  'CROSS-TABLE MATCH' AS test,
  (SELECT COUNT(DISTINCT email_hash) FROM `hulken.ads_data.shopify_live_orders_clean`
   WHERE email_hash IS NOT NULL AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS unique_order_hashes,
  (SELECT COUNT(DISTINCT email_hash) FROM `hulken.ads_data.shopify_live_customers_clean`
   WHERE email_hash IS NOT NULL AND email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS unique_customer_hashes,
  COUNT(*) AS matched_hashes,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL - no matches found' END AS result
FROM (
  SELECT DISTINCT o.email_hash
  FROM `hulken.ads_data.shopify_live_orders_clean` o
  JOIN `hulken.ads_data.shopify_live_customers_clean` c ON o.email_hash = c.email_hash
  WHERE o.email_hash IS NOT NULL
    AND o.email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
);

-- 3. ORPHAN CHECK: Orders without matching customer
SELECT
  'ORPHAN ORDERS' AS test,
  COUNT(*) AS orders_without_customer_match,
  CASE WHEN COUNT(*) < 1000 THEN 'PASS' ELSE 'WARNING - many orphans' END AS result
FROM `hulken.ads_data.shopify_live_orders_clean` o
LEFT JOIN `hulken.ads_data.shopify_live_customers_clean` c ON o.email_hash = c.email_hash
WHERE c.email_hash IS NULL
  AND o.email_hash IS NOT NULL
  AND o.email_hash != 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

-- 4. EMPTY HASH CHECK (hash of empty string = known value)
-- These indicate records where email was NULL/empty before hashing
SELECT
  'EMPTY HASH CHECK' AS test,
  source,
  empty_hash_count,
  total_count,
  ROUND(empty_hash_count / total_count * 100, 1) AS pct_empty,
  CASE WHEN empty_hash_count / total_count < 0.05 THEN 'PASS' ELSE 'WARNING - high empty rate' END AS result
FROM (
  SELECT 'orders_clean' AS source,
    COUNTIF(email_hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') AS empty_hash_count,
    COUNT(*) AS total_count
  FROM `hulken.ads_data.shopify_live_orders_clean`
  UNION ALL
  SELECT 'customers_clean',
    COUNTIF(email_hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    COUNT(*)
  FROM `hulken.ads_data.shopify_live_customers_clean`
);

-- 5. HASH COVERAGE: % of records with valid hashes
SELECT
  'HASH COVERAGE' AS test,
  source,
  total_rows,
  has_hash,
  ROUND(has_hash / total_rows * 100, 1) AS pct_coverage,
  CASE WHEN has_hash / total_rows > 0.95 THEN 'PASS' ELSE 'FAIL - low coverage' END AS result
FROM (
  SELECT 'orders_clean' AS source, COUNT(*) AS total_rows,
    COUNTIF(email_hash IS NOT NULL AND email_hash != '') AS has_hash
  FROM `hulken.ads_data.shopify_live_orders_clean`
  UNION ALL
  SELECT 'customers_clean', COUNT(*),
    COUNTIF(email_hash IS NOT NULL AND email_hash != '')
  FROM `hulken.ads_data.shopify_live_customers_clean`
);
