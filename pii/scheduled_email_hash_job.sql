-- ============================================================
-- SCHEDULED EMAIL HASH JOB
-- ============================================================
-- Purpose: Automatically hash new emails from Airbyte syncs
-- Schedule: Run hourly (or after each Airbyte sync)
--
-- Setup in BigQuery Console:
-- 1. Go to Scheduled Queries > Create Scheduled Query
-- 2. Name: "Hourly PII Hash Job"
-- 3. Schedule: Every 1 hour
-- 4. Location: US
-- 5. Paste this script
-- ============================================================


-- ============================================================
-- PART 1: HASH NEW EMAILS
-- ============================================================
-- Only updates rows where email exists but hash is missing

-- shopify_live_orders: Hash new emails
UPDATE `hulken.ads_data.shopify_live_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- shopify_live_customers: Hash new emails
UPDATE `hulken.ads_data.shopify_live_customers`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- shopify_orders: Hash new emails (if restored)
UPDATE `hulken.ads_data.shopify_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(customer_email))))
WHERE customer_email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- ============================================================
-- PART 2: OPTIONAL - NULLIFY AFTER HASH
-- ============================================================
-- Uncomment this section if you want automatic PII removal
-- CAUTION: Only enable after verifying hashing works correctly

/*
-- shopify_live_orders: Clear PII
UPDATE `hulken.ads_data.shopify_live_orders`
SET
  email = NULL,
  contact_email = NULL,
  phone = NULL,
  browser_ip = NULL
WHERE email_hash IS NOT NULL
  AND email IS NOT NULL;


-- shopify_live_customers: Clear PII
UPDATE `hulken.ads_data.shopify_live_customers`
SET
  email = NULL,
  phone = NULL,
  first_name = NULL,
  last_name = NULL
WHERE email_hash IS NOT NULL
  AND email IS NOT NULL;


-- shopify_orders: Clear PII
UPDATE `hulken.ads_data.shopify_orders`
SET
  customer_email = NULL,
  customer_firstName = NULL,
  customer_lastName = NULL
WHERE email_hash IS NOT NULL
  AND customer_email IS NOT NULL;
*/


-- ============================================================
-- PART 3: LOG / VERIFICATION (for monitoring)
-- ============================================================
-- This query runs at the end to log current state
-- Results can be viewed in scheduled query history

SELECT
  CURRENT_TIMESTAMP() as job_run_time,
  'shopify_live_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as unhashed_emails
FROM `hulken.ads_data.shopify_live_orders`

UNION ALL

SELECT
  CURRENT_TIMESTAMP() as job_run_time,
  'shopify_live_customers' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email IS NOT NULL) as rows_with_email,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as unhashed_emails
FROM `hulken.ads_data.shopify_live_customers`

UNION ALL

SELECT
  CURRENT_TIMESTAMP() as job_run_time,
  'shopify_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(customer_email IS NOT NULL) as rows_with_email,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(customer_email IS NOT NULL AND email_hash IS NULL) as unhashed_emails
FROM `hulken.ads_data.shopify_orders`;
