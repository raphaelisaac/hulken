-- ============================================================
-- SCHEDULED REFRESH: Shopify Clean Tables
-- ============================================================
-- Run daily after Airbyte sync (recommended: 10:00 UTC, after 09:00 sync)
-- Creates deduplicated + PII-hashed versions of raw Airbyte tables.
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


-- ============================================================
-- QUERY 2: Refresh shopify_live_customers_clean
-- ============================================================
-- Deduplicates on customer ID (keeps latest extraction)
-- Hashes PII fields, keeps first_name in clear (non-identifying alone)

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
