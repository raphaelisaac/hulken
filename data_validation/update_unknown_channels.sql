-- =============================================================================
-- UPDATE UNKNOWN CHANNELS IN SHOPIFY_UTM
-- =============================================================================
-- After running extract_order_channels.py, use these queries to verify and
-- update attribution status based on channel information.

-- Step 1: Check current attribution status distribution
SELECT attribution_status, COUNT(*) as order_count
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
ORDER BY order_count DESC;

-- Step 2: Check sales_channel distribution for UNKNOWN_CHANNEL orders
SELECT
    sales_channel,
    COUNT(*) as order_count,
    MIN(created_at) as first_order,
    MAX(created_at) as last_order
FROM `hulken.ads_data.shopify_utm`
WHERE attribution_status = 'UNKNOWN_CHANNEL'
GROUP BY 1
ORDER BY order_count DESC
LIMIT 20;

-- Step 3: Update attribution status based on channel handle
-- Run this AFTER extract_order_channels.py has populated sales_channel

-- Update Amazon orders
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'AMAZON_NO_TRACKING'
WHERE sales_channel IN ('amazon-us', 'amazon', 'amazon-ca', 'amazon-uk')
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update TikTok Shop orders
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'TIKTOK_SHOP'
WHERE sales_channel = 'tiktok'
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update Shop app orders (Shopify Shop mobile app)
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'SHOP_APP'
WHERE sales_channel = 'shop'
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update web/online store orders
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = CASE
    WHEN first_utm_source IS NOT NULL THEN 'HAS_UTM'
    WHEN first_landing_page IS NOT NULL THEN 'DIRECT_OR_ORGANIC'
    ELSE 'DIRECT_OR_ORGANIC'
  END
WHERE sales_channel IN ('web', 'online_store')
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update draft/manual orders
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'MANUAL_ORDER'
WHERE sales_channel = 'shopify_draft_order'
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update POS orders
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'POS_ORDER'
WHERE sales_channel IN ('pos', 'point_of_sale')
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Update other identified channels
UPDATE `hulken.ads_data.shopify_utm`
SET attribution_status = 'OTHER_CHANNEL'
WHERE sales_channel IS NOT NULL
  AND sales_channel NOT IN ('amazon-us', 'amazon', 'tiktok', 'shop', 'web',
                            'online_store', 'shopify_draft_order', 'pos', 'point_of_sale')
  AND attribution_status = 'UNKNOWN_CHANNEL';

-- Step 4: Verify final distribution
SELECT attribution_status, COUNT(*) as order_count
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
ORDER BY order_count DESC;

-- =============================================================================
-- ANALYSIS QUERIES
-- =============================================================================

-- Revenue by attribution status
SELECT
    attribution_status,
    COUNT(*) as order_count,
    ROUND(SUM(total_price), 2) as total_revenue,
    ROUND(AVG(total_price), 2) as avg_order_value
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
ORDER BY total_revenue DESC;

-- Sales channel by month
SELECT
    FORMAT_TIMESTAMP('%Y-%m', created_at) as month,
    sales_channel,
    COUNT(*) as orders,
    ROUND(SUM(total_price), 2) as revenue
FROM `hulken.ads_data.shopify_utm`
WHERE created_at >= '2024-01-01'
GROUP BY 1, 2
ORDER BY 1 DESC, orders DESC;

-- Orders without channel info (need investigation)
SELECT
    EXTRACT(YEAR FROM created_at) as year,
    COUNT(*) as orders_without_channel
FROM `hulken.ads_data.shopify_utm`
WHERE sales_channel IS NULL
GROUP BY 1
ORDER BY 1;
