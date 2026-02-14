-- Run this AFTER Facebook sync Job #125 completes
-- Creates 3 dedup views for the breakdown tables

-- 1. Action Type breakdown
CREATE OR REPLACE VIEW `hulken.ads_data.facebook_insights_action_type` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY ad_id, date_start, account_id, action_type
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights_action_type`
)
WHERE rn = 1;

-- 2. DMA breakdown
CREATE OR REPLACE VIEW `hulken.ads_data.facebook_insights_dma` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY ad_id, date_start, account_id, dma
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights_dma`
)
WHERE rn = 1;

-- 3. Platform & Device breakdown
CREATE OR REPLACE VIEW `hulken.ads_data.facebook_insights_platform_device` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY ad_id, date_start, account_id, publisher_platform, device_platform
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.facebook_ads_insights_platform_and_device`
)
WHERE rn = 1;
