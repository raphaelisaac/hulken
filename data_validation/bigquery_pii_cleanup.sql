-- ============================================================
-- BIGQUERY PII CLEANUP - Email Hashing & Column Removal
-- ============================================================
-- Run this AFTER verifying data is correct
-- This is IRREVERSIBLE - emails cannot be recovered after deletion
-- ============================================================

-- ============================================================
-- STEP 1: ADD email_hash COLUMNS
-- ============================================================

-- shopify_orders
ALTER TABLE `hulken.ads_data.shopify_orders`
ADD COLUMN IF NOT EXISTS email_hash STRING;

-- shopify_live_orders
ALTER TABLE `hulken.ads_data.shopify_live_orders`
ADD COLUMN IF NOT EXISTS email_hash STRING;

-- shopify_live_customers
ALTER TABLE `hulken.ads_data.shopify_live_customers`
ADD COLUMN IF NOT EXISTS email_hash STRING;


-- ============================================================
-- STEP 2: POPULATE email_hash FROM ORIGINAL EMAIL
-- ============================================================

-- shopify_orders
UPDATE `hulken.ads_data.shopify_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(customer_email))))
WHERE customer_email IS NOT NULL AND email_hash IS NULL;

-- shopify_live_orders
UPDATE `hulken.ads_data.shopify_live_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL AND email_hash IS NULL;

-- shopify_live_customers
UPDATE `hulken.ads_data.shopify_live_customers`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL AND email_hash IS NULL;


-- ============================================================
-- STEP 3: VERIFY HASH WAS CREATED
-- ============================================================

-- Check shopify_orders
SELECT
  'shopify_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(customer_email IS NOT NULL) as rows_with_email
FROM `hulken.ads_data.shopify_orders`;

-- Check shopify_live_orders
SELECT
  'shopify_live_orders' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL) as rows_with_email
FROM `hulken.ads_data.shopify_live_orders`;

-- Check shopify_live_customers
SELECT
  'shopify_live_customers' as table_name,
  COUNT(*) as total_rows,
  COUNTIF(email_hash IS NOT NULL) as rows_with_hash,
  COUNTIF(email IS NOT NULL) as rows_with_email
FROM `hulken.ads_data.shopify_live_customers`;


-- ============================================================
-- STEP 4: DELETE PII COLUMNS (RUN ONLY AFTER VERIFICATION)
-- ============================================================
-- ⚠️ DANGER ZONE - IRREVERSIBLE ⚠️

-- shopify_orders - Remove PII
ALTER TABLE `hulken.ads_data.shopify_orders`
DROP COLUMN IF EXISTS customer_email,
DROP COLUMN IF EXISTS customer_firstName,
DROP COLUMN IF EXISTS customer_lastName;

-- shopify_live_orders - Remove PII
ALTER TABLE `hulken.ads_data.shopify_live_orders`
DROP COLUMN IF EXISTS email,
DROP COLUMN IF EXISTS phone,
DROP COLUMN IF EXISTS browser_ip,
DROP COLUMN IF EXISTS contact_email,
DROP COLUMN IF EXISTS billing_address,
DROP COLUMN IF EXISTS token;

-- shopify_live_customers - Remove PII
ALTER TABLE `hulken.ads_data.shopify_live_customers`
DROP COLUMN IF EXISTS email,
DROP COLUMN IF EXISTS phone,
DROP COLUMN IF EXISTS first_name,
DROP COLUMN IF EXISTS last_name,
DROP COLUMN IF EXISTS addresses,
DROP COLUMN IF EXISTS default_address;


-- ============================================================
-- STEP 5: VERIFY PII COLUMNS ARE GONE
-- ============================================================

SELECT column_name
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'shopify_orders'
AND column_name IN ('customer_email', 'customer_firstName', 'customer_lastName', 'email_hash');

SELECT column_name
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'shopify_live_orders'
AND column_name IN ('email', 'phone', 'browser_ip', 'email_hash');

SELECT column_name
FROM `hulken.ads_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'shopify_live_customers'
AND column_name IN ('email', 'phone', 'first_name', 'last_name', 'email_hash');
