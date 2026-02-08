-- ============================================================
-- HASH ALL EMAILS CONSISTENTLY ACROSS TABLES
-- ============================================================
-- IMPORTANT: This uses the SAME hash function everywhere to ensure
-- the same email produces the same hash across all tables.
--
-- Hash function: TO_HEX(SHA256(LOWER(TRIM(email))))
-- This ensures:
--   - Lowercase normalization (john@EMAIL.com = john@email.com)
--   - Whitespace trimming (removes leading/trailing spaces)
--   - Hex encoding for readable output
-- ============================================================

-- ============================================================
-- STEP 1: ADD email_hash COLUMNS (if they don't exist)
-- ============================================================

-- shopify_orders (should already have this)
ALTER TABLE `hulken.ads_data.shopify_orders`
ADD COLUMN IF NOT EXISTS email_hash STRING;

-- shopify_live_orders
ALTER TABLE `hulken.ads_data.shopify_live_orders`
ADD COLUMN IF NOT EXISTS email_hash STRING;

-- shopify_live_customers
ALTER TABLE `hulken.ads_data.shopify_live_customers`
ADD COLUMN IF NOT EXISTS email_hash STRING;


-- ============================================================
-- STEP 2: HASH EMAILS IN shopify_orders
-- ============================================================

UPDATE `hulken.ads_data.shopify_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(customer_email))))
WHERE customer_email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- ============================================================
-- STEP 3: HASH EMAILS IN shopify_live_orders
-- ============================================================

UPDATE `hulken.ads_data.shopify_live_orders`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- ============================================================
-- STEP 4: HASH EMAILS IN shopify_live_customers
-- ============================================================

UPDATE `hulken.ads_data.shopify_live_customers`
SET email_hash = TO_HEX(SHA256(LOWER(TRIM(email))))
WHERE email IS NOT NULL
  AND (email_hash IS NULL OR email_hash = '');


-- ============================================================
-- STEP 5: VERIFICATION - Check hash counts
-- ============================================================

SELECT 'shopify_orders' as table_name,
       COUNT(*) as total_rows,
       COUNTIF(email_hash IS NOT NULL) as with_hash,
       COUNTIF(customer_email IS NOT NULL) as with_email
FROM `hulken.ads_data.shopify_orders`
UNION ALL
SELECT 'shopify_live_orders' as table_name,
       COUNT(*) as total_rows,
       COUNTIF(email_hash IS NOT NULL) as with_hash,
       COUNTIF(email IS NOT NULL) as with_email
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'shopify_live_customers' as table_name,
       COUNT(*) as total_rows,
       COUNTIF(email_hash IS NOT NULL) as with_hash,
       COUNTIF(email IS NOT NULL) as with_email
FROM `hulken.ads_data.shopify_live_customers`;


-- ============================================================
-- STEP 6: VERIFICATION - Cross-table hash consistency
-- ============================================================
-- This query checks that the same email produces the same hash
-- across different tables.

WITH common_emails AS (
  -- Find emails that appear in both live_orders and live_customers
  SELECT DISTINCT o.email
  FROM `hulken.ads_data.shopify_live_orders` o
  INNER JOIN `hulken.ads_data.shopify_live_customers` c
    ON LOWER(TRIM(o.email)) = LOWER(TRIM(c.email))
  WHERE o.email IS NOT NULL
  LIMIT 10
)
SELECT
  e.email,
  TO_HEX(SHA256(LOWER(TRIM(e.email)))) as computed_hash,
  (SELECT email_hash FROM `hulken.ads_data.shopify_live_orders`
   WHERE LOWER(TRIM(email)) = LOWER(TRIM(e.email)) LIMIT 1) as orders_hash,
  (SELECT email_hash FROM `hulken.ads_data.shopify_live_customers`
   WHERE LOWER(TRIM(email)) = LOWER(TRIM(e.email)) LIMIT 1) as customers_hash
FROM common_emails e;
