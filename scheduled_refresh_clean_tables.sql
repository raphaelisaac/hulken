-- ============================================================
-- SCHEDULED REFRESH: Shopify Clean Tables
-- ============================================================
-- Run daily after Airbyte sync (recommended: 10:00 UTC, after 09:00 sync)
-- Creates deduplicated + PII-hashed versions of raw Airbyte tables.
--
-- FIX 2026-02-12: Preserves existing hashes when raw emails are NULL.
-- The PII nullify script wipes emails from raw tables, but Airbyte
-- re-syncs with fresh emails. This script now:
--   1. Saves existing hashes from the current clean table
--   2. Rebuilds the clean table (dedup + hash any available emails)
--   3. Restores preserved hashes for rows where email was already NULL
--
-- Setup in BigQuery Console:
--   1. Go to BigQuery > Scheduled Queries > Create
--   2. Paste each query below as a separate scheduled query
--   3. Schedule: Daily at 10:00 UTC
--   4. Name: "Refresh shopify_live_orders_clean" / "Refresh shopify_live_customers_clean"
--
-- Created: 2026-02-12
-- ============================================================


-- ============================================================
-- QUERY 1: Refresh shopify_live_orders_clean
-- ============================================================
-- Deduplicates on order ID (keeps latest extraction)
-- Hashes PII fields (email, phone) and removes raw PII columns
-- Preserves existing hashes when raw email has been nullified

-- Step 1a: Save existing hashes before replacing the table
CREATE TEMP TABLE _prev_orders_hashes AS
SELECT id, email_hash, phone_hash
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE email_hash IS NOT NULL OR phone_hash IS NOT NULL;

-- Step 1b: Rebuild clean table with dedup + hash
CREATE OR REPLACE TABLE `hulken.ads_data.shopify_live_orders_clean` AS
SELECT * EXCEPT(rn, email, phone, billing_address, shipping_address, contact_email),
  CASE WHEN email IS NOT NULL AND email != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(email)))) ELSE NULL END AS email_hash,
  CASE WHEN phone IS NOT NULL AND phone != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(phone)))) ELSE NULL END AS phone_hash
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY _airbyte_extracted_at DESC) AS rn
  FROM `hulken.ads_data.shopify_live_orders`
)
WHERE rn = 1;

-- Step 1c: Restore hashes for rows where raw email was already nullified
UPDATE `hulken.ads_data.shopify_live_orders_clean` AS c
SET
  c.email_hash = COALESCE(c.email_hash, p.email_hash),
  c.phone_hash = COALESCE(c.phone_hash, p.phone_hash)
FROM _prev_orders_hashes AS p
WHERE c.id = p.id
  AND (c.email_hash IS NULL OR c.phone_hash IS NULL);

DROP TABLE _prev_orders_hashes;


-- ============================================================
-- QUERY 2: Refresh shopify_live_customers_clean
-- ============================================================
-- Deduplicates on customer ID (keeps latest extraction)
-- Hashes PII fields, keeps first_name in clear (non-identifying alone)
-- Preserves existing hashes when raw PII has been nullified

-- Step 2a: Save existing hashes
CREATE TEMP TABLE _prev_customers_hashes AS
SELECT id, email_hash, phone_hash, last_name_hash, addresses_hash,
       default_address_hash, first_name_hash
FROM `hulken.ads_data.shopify_live_customers_clean`
WHERE email_hash IS NOT NULL OR phone_hash IS NOT NULL
   OR last_name_hash IS NOT NULL OR first_name_hash IS NOT NULL;

-- Step 2b: Rebuild clean table
CREATE OR REPLACE TABLE `hulken.ads_data.shopify_live_customers_clean` AS
SELECT * EXCEPT(rn, email, phone, first_name, last_name, addresses, default_address),
  first_name,
  CASE WHEN email IS NOT NULL AND email != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(email)))) ELSE NULL END AS email_hash,
  CASE WHEN phone IS NOT NULL AND phone != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(phone)))) ELSE NULL END AS phone_hash,
  CASE WHEN last_name IS NOT NULL AND last_name != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(last_name)))) ELSE NULL END AS last_name_hash,
  CASE WHEN addresses IS NOT NULL
    THEN TO_HEX(SHA256(CAST(FORMAT('%t', addresses) AS BYTES))) ELSE NULL END AS addresses_hash,
  CASE WHEN default_address IS NOT NULL
    THEN TO_HEX(SHA256(CAST(FORMAT('%t', default_address) AS BYTES))) ELSE NULL END AS default_address_hash,
  CASE WHEN first_name IS NOT NULL AND first_name != ''
    THEN TO_HEX(SHA256(LOWER(TRIM(first_name)))) ELSE NULL END AS first_name_hash
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY _airbyte_extracted_at DESC) AS rn
  FROM `hulken.ads_data.shopify_live_customers`
)
WHERE rn = 1;

-- Step 2c: Restore hashes for rows where raw PII was already nullified
UPDATE `hulken.ads_data.shopify_live_customers_clean` AS c
SET
  c.email_hash = COALESCE(c.email_hash, p.email_hash),
  c.phone_hash = COALESCE(c.phone_hash, p.phone_hash),
  c.last_name_hash = COALESCE(c.last_name_hash, p.last_name_hash),
  c.addresses_hash = COALESCE(c.addresses_hash, p.addresses_hash),
  c.default_address_hash = COALESCE(c.default_address_hash, p.default_address_hash),
  c.first_name_hash = COALESCE(c.first_name_hash, p.first_name_hash)
FROM _prev_customers_hashes AS p
WHERE c.id = p.id
  AND (c.email_hash IS NULL OR c.phone_hash IS NULL
    OR c.last_name_hash IS NULL OR c.first_name_hash IS NULL);

DROP TABLE _prev_customers_hashes;


-- ============================================================
-- QUERY 3: Refresh shopify_live_transactions (optional dedup)
-- ============================================================
-- Transactions may also have duplicates from incremental sync

-- CREATE OR REPLACE TABLE `hulken.ads_data.shopify_live_transactions_clean` AS
-- SELECT * EXCEPT(rn)
-- FROM (
--   SELECT *,
--     ROW_NUMBER() OVER (PARTITION BY id ORDER BY _airbyte_extracted_at DESC) AS rn
--   FROM `hulken.ads_data.shopify_live_transactions`
-- )
-- WHERE rn = 1;
