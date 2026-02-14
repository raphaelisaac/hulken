-- TikTok View Deduplication Fix
-- ================================
-- Problem: Airbyte's incremental sync re-extracts the last 7 days on each run,
-- creating duplicate rows in the raw tables. The original views had no deduplication,
-- causing metrics to be counted 2-3x.
--
-- Fix: Add ROW_NUMBER() partitioned by the natural key, keeping only the latest extraction.
-- Applied: 2026-02-12
--
-- Verification: After applying, tiktok_ads_reports_daily spend for Feb 4-10 went from
-- $51,164.94 (doubled) to $18,826.52 (correct, matches TikTok API exactly).

-- 1. Ads Reports Daily - deduplicate on (ad_id, stat_time_day)
CREATE OR REPLACE VIEW `hulken.ads_data.tiktok_ads_reports_daily` AS
SELECT
  ad_id,
  adgroup_id,
  campaign_id,
  advertiser_id,
  DATE(stat_time_day) AS report_date,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64) AS spend,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64) AS impressions,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.clicks') AS INT64) AS clicks,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.conversion') AS INT64) AS conversions,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.complete_payment') AS INT64) AS purchases,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cost_per_conversion') AS FLOAT64) AS cost_per_conversion,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cpc') AS FLOAT64) AS cpc,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.cpm') AS FLOAT64) AS cpm,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.ctr') AS FLOAT64) AS ctr,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.reach') AS INT64) AS reach
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY ad_id, DATE(stat_time_day)
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.tiktokads_reports_daily`
)
WHERE rn = 1;

-- 2. Ad Groups Reports Daily - deduplicate on (adgroup_id, stat_time_day)
CREATE OR REPLACE VIEW `hulken.ads_data.tiktok_ad_groups_reports_daily` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY adgroup_id, DATE(stat_time_day)
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.tiktokad_groups_reports_daily`
)
WHERE rn = 1;

-- 3. Campaigns Reports Daily - deduplicate on (campaign_id, stat_time_day)
CREATE OR REPLACE VIEW `hulken.ads_data.tiktok_campaigns_reports_daily` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY campaign_id, DATE(stat_time_day)
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.tiktokcampaigns_reports_daily`
)
WHERE rn = 1;

-- 4. Advertisers Reports Daily - deduplicate on (advertiser_id, stat_time_day)
CREATE OR REPLACE VIEW `hulken.ads_data.tiktok_advertisers_reports_daily` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY advertiser_id, DATE(stat_time_day)
      ORDER BY _airbyte_extracted_at DESC
    ) AS rn
  FROM `hulken.ads_data.tiktokadvertisers_reports_daily`
)
WHERE rn = 1;
