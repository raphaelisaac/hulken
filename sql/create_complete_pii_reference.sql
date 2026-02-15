-- ============================================================
-- COMPLETE PII HASH REFERENCE TABLE
-- ============================================================
-- Creates a comprehensive PII hash reference for ALL sensitive fields
--
-- IMPORTANT: NULL values are PRESERVED (not hashed)
--   - Reference table contains only non-NULL values
--   - NULL means "data missing" (no phone provided, no address, etc.)
--   - When used in unified tables: NULL stays NULL
--
-- PII Fields Covered:
--   1. email_hash
--   2. phone_hash
--   3. first_name_hash
--   4. last_name_hash
--   5. addresses_hash
--   6. default_address_hash
--   7. browser_ip (will be hashed for consistency)
--
-- Created: 2026-02-15
-- ============================================================


-- ============================================================
-- PART 1: EMAIL HASH REFERENCE
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_email_reference` AS

WITH all_emails AS (
  -- Shopify customers emails
  SELECT DISTINCT
    email_hash AS email_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE email_hash IS NOT NULL  -- NULL values excluded

  UNION DISTINCT

  -- Shopify orders emails
  SELECT DISTINCT
    email_hash AS email_hash_original,
    'shopify_orders' AS source
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE email_hash IS NOT NULL  -- NULL values excluded
)

SELECT
  email_hash_original,
  TO_HEX(SHA256(email_hash_original)) AS email_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_emails
GROUP BY email_hash_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 2: PHONE HASH REFERENCE
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_phone_reference` AS

WITH all_phones AS (
  -- Shopify customers phones
  SELECT DISTINCT
    phone_hash AS phone_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE phone_hash IS NOT NULL  -- NULL values excluded

  UNION DISTINCT

  -- Shopify orders phones
  SELECT DISTINCT
    phone_hash AS phone_hash_original,
    'shopify_orders' AS source
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE phone_hash IS NOT NULL  -- NULL values excluded
)

SELECT
  phone_hash_original,
  TO_HEX(SHA256(phone_hash_original)) AS phone_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_phones
GROUP BY phone_hash_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 3: FIRST NAME HASH REFERENCE
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_first_name_reference` AS

WITH all_first_names AS (
  -- Shopify customers first names
  SELECT DISTINCT
    first_name_hash AS first_name_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE first_name_hash IS NOT NULL  -- NULL values excluded
)

SELECT
  first_name_hash_original,
  TO_HEX(SHA256(first_name_hash_original)) AS first_name_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_first_names
GROUP BY first_name_hash_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 4: LAST NAME HASH REFERENCE
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_last_name_reference` AS

WITH all_last_names AS (
  -- Shopify customers last names
  SELECT DISTINCT
    last_name_hash AS last_name_hash_original,
    'shopify_customers' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE last_name_hash IS NOT NULL  -- NULL values excluded
)

SELECT
  last_name_hash_original,
  TO_HEX(SHA256(last_name_hash_original)) AS last_name_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_last_names
GROUP BY last_name_hash_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 5: ADDRESS HASH REFERENCE
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_address_reference` AS

WITH all_addresses AS (
  -- Shopify customers addresses
  SELECT DISTINCT
    addresses_hash AS address_hash_original,
    'shopify_customers_addresses' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE addresses_hash IS NOT NULL  -- NULL values excluded

  UNION DISTINCT

  -- Shopify customers default address
  SELECT DISTINCT
    default_address_hash AS address_hash_original,
    'shopify_customers_default_address' AS source
  FROM `hulken.ads_data.shopify_live_customers_clean`
  WHERE default_address_hash IS NOT NULL  -- NULL values excluded
)

SELECT
  address_hash_original,
  TO_HEX(SHA256(address_hash_original)) AS address_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_addresses
GROUP BY address_hash_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 6: BROWSER IP REFERENCE (from orders)
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.pii_ip_reference` AS

WITH all_ips AS (
  -- Shopify orders browser IPs
  SELECT DISTINCT
    browser_ip AS ip_original,
    'shopify_orders' AS source
  FROM `hulken.ads_data.shopify_live_orders_clean`
  WHERE browser_ip IS NOT NULL  -- NULL values excluded
    AND browser_ip != ''  -- Empty strings also excluded
)

SELECT
  ip_original,
  TO_HEX(SHA256(ip_original)) AS ip_hash_consistent,
  STRING_AGG(DISTINCT source, ', ') AS sources,
  COUNT(DISTINCT source) AS source_count
FROM all_ips
GROUP BY ip_original
ORDER BY source_count DESC;


-- ============================================================
-- PART 7: MASTER PII REFERENCE (ALL FIELDS)
-- ============================================================
-- Combined reference table for easy lookup

CREATE OR REPLACE TABLE `hulken.ads_data.pii_master_reference` AS

SELECT
  'email' AS pii_field,
  email_hash_original AS original_value,
  email_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_email_reference`

UNION ALL

SELECT
  'phone' AS pii_field,
  phone_hash_original AS original_value,
  phone_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_phone_reference`

UNION ALL

SELECT
  'first_name' AS pii_field,
  first_name_hash_original AS original_value,
  first_name_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_first_name_reference`

UNION ALL

SELECT
  'last_name' AS pii_field,
  last_name_hash_original AS original_value,
  last_name_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_last_name_reference`

UNION ALL

SELECT
  'address' AS pii_field,
  address_hash_original AS original_value,
  address_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_address_reference`

UNION ALL

SELECT
  'ip' AS pii_field,
  ip_original AS original_value,
  ip_hash_consistent AS consistent_hash,
  sources,
  source_count
FROM `hulken.ads_data.pii_ip_reference`;


-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

-- Check 1: Verify no NULL values in reference tables
SELECT
  'Email Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(email_hash_original IS NULL) AS null_original,
  COUNTIF(email_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_email_reference`

UNION ALL

SELECT
  'Phone Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(phone_hash_original IS NULL) AS null_original,
  COUNTIF(phone_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_phone_reference`

UNION ALL

SELECT
  'First Name Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(first_name_hash_original IS NULL) AS null_original,
  COUNTIF(first_name_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_first_name_reference`

UNION ALL

SELECT
  'Last Name Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(last_name_hash_original IS NULL) AS null_original,
  COUNTIF(last_name_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_last_name_reference`

UNION ALL

SELECT
  'Address Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(address_hash_original IS NULL) AS null_original,
  COUNTIF(address_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_address_reference`

UNION ALL

SELECT
  'IP Reference' AS table_name,
  COUNT(*) AS total_rows,
  COUNTIF(ip_original IS NULL) AS null_original,
  COUNTIF(ip_hash_consistent IS NULL) AS null_consistent
FROM `hulken.ads_data.pii_ip_reference`;

-- Expected: All null_original and null_consistent should be 0


-- Check 2: Summary of all PII types
SELECT
  pii_field,
  COUNT(*) AS unique_values,
  SUM(source_count) AS total_occurrences,
  ROUND(AVG(source_count), 2) AS avg_sources_per_value
FROM `hulken.ads_data.pii_master_reference`
GROUP BY pii_field
ORDER BY unique_values DESC;


-- Check 3: Find PII values that appear in multiple sources (good for cross-referencing)
SELECT
  pii_field,
  COUNT(*) AS values_in_multiple_sources
FROM `hulken.ads_data.pii_master_reference`
WHERE source_count > 1
GROUP BY pii_field
ORDER BY values_in_multiple_sources DESC;


-- ============================================================
-- NOTES
-- ============================================================
-- 1. NULL values are EXCLUDED from all reference tables
--    - NULL means "data missing" (no phone, no address, etc.)
--    - This is semantically different from having a value
--
-- 2. When using these references in unified tables:
--    - Always use LEFT JOIN (not INNER JOIN)
--    - Use COALESCE(ref.hash_consistent, original) pattern
--    - This preserves NULL values
--
-- 3. Empty strings are treated as NULL for IPs
--    - WHERE ip != '' excludes empty strings
--
-- 4. All hash functions use SHA256 for consistency
--    - Same value across all tables = same hash
--
-- 5. Master reference table combines all PII types
--    - Easy to query all PII in one place
--    - Use pii_field to filter by type
--
-- 6. Backward compatibility:
--    - Keep pii_hash_reference (email only) for legacy code
--    - New code should use specific tables (pii_email_reference, etc.)
--

-- ============================================================
-- BACKWARD COMPATIBILITY (OPTIONAL)
-- ============================================================
-- Keep old pii_hash_reference table name pointing to email reference
-- for backward compatibility with existing code

CREATE OR REPLACE VIEW `hulken.ads_data.pii_hash_reference` AS
SELECT
  email_hash_original AS email_hash_original,
  email_hash_consistent AS email_hash_consistent,
  sources,
  source_count
FROM `hulken.ads_data.pii_email_reference`;

