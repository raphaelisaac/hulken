-- ============================================================
-- SCHEDULED EMAIL HASH JOB
-- ============================================================
-- Run this daily/hourly to hash new emails from Airbyte syncs
-- Then nullify the original email (keeps column but removes PII)
-- ============================================================

-- ============================================================
-- STEP 1: HASH NEW EMAILS (where email exists but hash is NULL)
-- ============================================================

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


-- ============================================================
-- STEP 2: NULLIFY ORIGINAL EMAILS (after hash is created)
-- ============================================================

-- shopify_live_orders: Clear original email
UPDATE `hulken.ads_data.shopify_live_orders`
SET email = NULL,
    contact_email = NULL,
    phone = NULL,
    browser_ip = NULL
WHERE email_hash IS NOT NULL
  AND email IS NOT NULL;

-- shopify_live_customers: Clear original email
UPDATE `hulken.ads_data.shopify_live_customers`
SET email = NULL,
    phone = NULL
WHERE email_hash IS NOT NULL
  AND email IS NOT NULL;


-- ============================================================
-- VERIFICATION QUERY (run after job to confirm)
-- ============================================================

SELECT
  'shopify_live_orders' as table_name,
  COUNTIF(email IS NOT NULL) as emails_remaining,
  COUNTIF(email_hash IS NOT NULL) as hashes_created
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT
  'shopify_live_customers' as table_name,
  COUNTIF(email IS NOT NULL) as emails_remaining,
  COUNTIF(email_hash IS NOT NULL) as hashes_created
FROM `hulken.ads_data.shopify_live_customers`;
