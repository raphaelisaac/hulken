-- ============================================================
-- NULLIFY PII AFTER HASH (CORRECT APPROACH)
-- ============================================================
-- CRITICAL: This script NULLIFIES values, it does NOT delete columns!
--
-- WRONG:  ALTER TABLE DROP COLUMN email   -- NEVER DO THIS
-- RIGHT:  UPDATE SET email = NULL         -- ALWAYS DO THIS
--
-- Why keep the columns?
-- 1. Airbyte needs columns to exist for sync
-- 2. Schema changes break time-travel recovery
-- 3. We may need to re-populate from source later
-- 4. Column deletion is irreversible
-- ============================================================


-- ============================================================
-- PRE-FLIGHT CHECK: Verify hashes exist before nullifying
-- ============================================================

-- DO NOT RUN THE UPDATE STATEMENTS BELOW UNTIL THIS CHECK PASSES

SELECT
  'shopify_orders' as table_name,
  COUNTIF(customer_email IS NOT NULL) as emails_to_nullify,
  COUNTIF(customer_email IS NOT NULL AND email_hash IS NULL) as would_lose_data
FROM `hulken.ads_data.shopify_orders`
UNION ALL
SELECT
  'shopify_live_orders' as table_name,
  COUNTIF(email IS NOT NULL) as emails_to_nullify,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as would_lose_data
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  COUNTIF(email IS NOT NULL) as emails_to_nullify,
  COUNTIF(email IS NOT NULL AND email_hash IS NULL) as would_lose_data
FROM `hulken.ads_data.shopify_live_customers`;

-- STOP! If 'would_lose_data' > 0, DO NOT proceed. Run hash_all_emails.sql first.


-- ============================================================
-- STEP 1: NULLIFY shopify_orders PII
-- ============================================================
-- Only nullify rows that HAVE a hash (safety check)

UPDATE `hulken.ads_data.shopify_orders`
SET
  customer_email = NULL,
  customer_firstName = NULL,
  customer_lastName = NULL
WHERE email_hash IS NOT NULL
  AND (customer_email IS NOT NULL OR customer_firstName IS NOT NULL OR customer_lastName IS NOT NULL);


-- ============================================================
-- STEP 2: NULLIFY shopify_live_orders PII
-- ============================================================

UPDATE `hulken.ads_data.shopify_live_orders`
SET
  email = NULL,
  contact_email = NULL,
  phone = NULL,
  browser_ip = NULL
  -- NOTE: token and billing_address are also PII but may be needed for reconciliation
  -- Uncomment below if you want to nullify them too:
  -- , token = NULL
  -- , billing_address = NULL
WHERE email_hash IS NOT NULL
  AND (email IS NOT NULL OR phone IS NOT NULL OR browser_ip IS NOT NULL);


-- ============================================================
-- STEP 3: NULLIFY shopify_live_customers PII
-- ============================================================

UPDATE `hulken.ads_data.shopify_live_customers`
SET
  email = NULL,
  phone = NULL,
  first_name = NULL,
  last_name = NULL
  -- NOTE: addresses and default_address may contain valuable geo data
  -- Uncomment below if you want to nullify them completely:
  -- , addresses = NULL
  -- , default_address = NULL
WHERE email_hash IS NOT NULL
  AND (email IS NOT NULL OR phone IS NOT NULL OR first_name IS NOT NULL OR last_name IS NOT NULL);


-- ============================================================
-- VERIFICATION: Confirm PII is gone but columns exist
-- ============================================================

SELECT
  'shopify_orders' as table_name,
  COUNTIF(customer_email IS NOT NULL) as remaining_emails,
  COUNTIF(email_hash IS NOT NULL) as hashes_preserved,
  'customer_email, customer_firstName, customer_lastName columns still exist' as column_status
FROM `hulken.ads_data.shopify_orders`

UNION ALL

SELECT
  'shopify_live_orders' as table_name,
  COUNTIF(email IS NOT NULL) as remaining_emails,
  COUNTIF(email_hash IS NOT NULL) as hashes_preserved,
  'email, phone, browser_ip columns still exist' as column_status
FROM `hulken.ads_data.shopify_live_orders`

UNION ALL

SELECT
  'shopify_live_customers' as table_name,
  COUNTIF(email IS NOT NULL) as remaining_emails,
  COUNTIF(email_hash IS NOT NULL) as hashes_preserved,
  'email, phone, first_name, last_name columns still exist' as column_status
FROM `hulken.ads_data.shopify_live_customers`;

-- Expected result: remaining_emails = 0, hashes_preserved = (original count)


-- ============================================================
-- CONFIRM COLUMNS STILL EXIST
-- ============================================================

SELECT table_name, column_name
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('shopify_orders', 'shopify_live_orders', 'shopify_live_customers')
  AND column_name IN (
    'customer_email', 'customer_firstName', 'customer_lastName',
    'email', 'phone', 'browser_ip', 'contact_email',
    'first_name', 'last_name', 'addresses', 'default_address',
    'email_hash'
  )
ORDER BY table_name, column_name;

-- All columns should still appear in this list
