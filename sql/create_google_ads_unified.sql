-- ============================================================
-- GOOGLE ADS UNIFIED TABLE
-- ============================================================
-- Consolidates Google Ads campaign stats from google_Ads dataset
-- into a clean unified table in ads_data
--
-- Created: 2026-02-15
-- ============================================================

CREATE OR REPLACE TABLE `hulken.ads_data.google_ads_unified` AS

WITH campaign_info AS (
  SELECT
    campaign_id,
    campaign_name,
    campaign_status
  FROM `hulken.google_Ads.ads_Campaign_4354001000`
)

SELECT
  -- ========== INDEXES ==========
  CONCAT(
    CAST(s.segments_date AS STRING),
    '_',
    COALESCE(CAST(s.campaign_id AS STRING), 'unknown')
  ) AS ga_row_id,
  s.segments_date AS date,
  s.campaign_id AS ga_campaign_id,

  -- ========== GROUPBY FEATURES ==========
  c.campaign_name AS ga_campaign_name,
  c.campaign_status AS ga_campaign_status,
  s.segments_device AS ga_device,
  s.segments_ad_network_type AS ga_network_type,

  -- ========== TARGETS (Metrics) ==========
  CAST(s.metrics_cost_micros AS FLOAT64) / 1000000 AS ga_spend,
  s.metrics_impressions AS ga_impressions,
  s.metrics_clicks AS ga_clicks,
  s.metrics_conversions AS ga_conversions,
  CAST(s.metrics_conversions_value AS FLOAT64) AS ga_conversion_value,

  -- ========== CALCULATED METRICS ==========
  SAFE_DIVIDE(s.metrics_clicks, s.metrics_impressions) * 100 AS ga_ctr_percent,
  SAFE_DIVIDE(
    CAST(s.metrics_cost_micros AS FLOAT64) / 1000000,
    s.metrics_clicks
  ) AS ga_cpc,
  SAFE_DIVIDE(
    CAST(s.metrics_cost_micros AS FLOAT64) / 1000000,
    s.metrics_impressions
  ) * 1000 AS ga_cpm,
  SAFE_DIVIDE(
    s.metrics_conversions,
    s.metrics_clicks
  ) * 100 AS ga_conversion_rate,
  SAFE_DIVIDE(
    CAST(s.metrics_cost_micros AS FLOAT64) / 1000000,
    NULLIF(s.metrics_conversions, 0)
  ) AS ga_cpa,
  SAFE_DIVIDE(
    CAST(s.metrics_conversions_value AS FLOAT64),
    CAST(s.metrics_cost_micros AS FLOAT64) / 1000000
  ) AS ga_roas

FROM `hulken.google_Ads.ads_CampaignStats_4354001000` s
LEFT JOIN campaign_info c
  ON s.campaign_id = c.campaign_id
WHERE s.segments_date IS NOT NULL;

-- Verify
SELECT
  'google_ads_unified' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT ga_campaign_id) AS unique_campaigns,
  SUM(ga_spend) AS total_spend,
  SUM(ga_conversions) AS total_conversions,
  SAFE_DIVIDE(SUM(ga_conversion_value), SUM(ga_spend)) AS avg_roas
FROM `hulken.ads_data.google_ads_unified`;
