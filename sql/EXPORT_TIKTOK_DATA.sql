-- =====================================================
-- EXPORT TIKTOK ADS DATA - HULKEN
-- À exécuter dans BigQuery Console puis exporter en CSV
-- =====================================================

-- EXPORT 1: Données détaillées par jour/ad (33,978 lignes)
-- Utiliser pour analyse granulaire
SELECT
  DATE(stat_time_day) as date,
  JSON_VALUE(metrics, '$.campaign_name') as campaign_name,
  JSON_VALUE(metrics, '$.adgroup_name') as adgroup_name,
  JSON_VALUE(metrics, '$.ad_name') as ad_name,
  ROUND(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64), 2) as spend_usd,
  CAST(JSON_VALUE(metrics, '$.impressions') AS INT64) as impressions,
  CAST(JSON_VALUE(metrics, '$.clicks') AS INT64) as clicks,
  CAST(JSON_VALUE(metrics, '$.conversion') AS INT64) as conversions,
  CAST(JSON_VALUE(metrics, '$.complete_payment') AS INT64) as purchases,
  ROUND(CAST(JSON_VALUE(metrics, '$.ctr') AS FLOAT64), 2) as ctr_pct,
  ROUND(CAST(JSON_VALUE(metrics, '$.cpc') AS FLOAT64), 2) as cpc_usd,
  ROUND(CAST(JSON_VALUE(metrics, '$.cpm') AS FLOAT64), 2) as cpm_usd,
  ROUND(CAST(JSON_VALUE(metrics, '$.cost_per_conversion') AS FLOAT64), 2) as cpa_usd,
  CAST(JSON_VALUE(metrics, '$.video_play_actions') AS INT64) as video_plays,
  CAST(JSON_VALUE(metrics, '$.video_views_p25') AS INT64) as video_25pct,
  CAST(JSON_VALUE(metrics, '$.video_views_p50') AS INT64) as video_50pct,
  CAST(JSON_VALUE(metrics, '$.video_views_p75') AS INT64) as video_75pct,
  CAST(JSON_VALUE(metrics, '$.video_views_p100') AS INT64) as video_100pct,
  ROUND(CAST(JSON_VALUE(metrics, '$.average_video_play') AS FLOAT64), 2) as avg_watch_time_sec,
  CAST(JSON_VALUE(metrics, '$.likes') AS INT64) as likes,
  CAST(JSON_VALUE(metrics, '$.comments') AS INT64) as comments,
  CAST(JSON_VALUE(metrics, '$.shares') AS INT64) as shares,
  CAST(JSON_VALUE(metrics, '$.engagements') AS INT64) as engagements
FROM `hulken.ads_data.tiktok_ads_reports_daily`
ORDER BY date DESC, campaign_name, ad_name;


-- =====================================================
-- EXPORT 2: Résumé par campagne (pour vue d'ensemble)
-- =====================================================
SELECT
  JSON_VALUE(metrics, '$.campaign_name') as campaign_name,
  MIN(DATE(stat_time_day)) as date_debut,
  MAX(DATE(stat_time_day)) as date_fin,
  COUNT(DISTINCT DATE(stat_time_day)) as nb_jours_actifs,
  COUNT(DISTINCT JSON_VALUE(metrics, '$.ad_name')) as nb_ads,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)), 2) as total_spend_usd,
  SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS INT64)) as total_impressions,
  SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS INT64)) as total_clicks,
  SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS INT64)) as total_conversions,
  SUM(CAST(JSON_VALUE(metrics, '$.complete_payment') AS INT64)) as total_purchases,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS FLOAT64)), 0) * 100, 2) as ctr_pct,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS FLOAT64)), 0), 2) as avg_cpc_usd,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS FLOAT64)), 0), 2) as avg_cpa_usd,
  SUM(CAST(JSON_VALUE(metrics, '$.video_play_actions') AS INT64)) as total_video_plays,
  SUM(CAST(JSON_VALUE(metrics, '$.likes') AS INT64)) as total_likes,
  SUM(CAST(JSON_VALUE(metrics, '$.shares') AS INT64)) as total_shares
FROM `hulken.ads_data.tiktok_ads_reports_daily`
GROUP BY campaign_name
ORDER BY total_spend_usd DESC;


-- =====================================================
-- EXPORT 3: Tendance mensuelle
-- =====================================================
SELECT
  FORMAT_DATE('%Y-%m', DATE(stat_time_day)) as mois,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)), 2) as spend_usd,
  SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS INT64)) as impressions,
  SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS INT64)) as clicks,
  SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS INT64)) as conversions,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS FLOAT64)), 0) * 100, 2) as ctr_pct,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS FLOAT64)), 0), 2) as cpc_usd,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS FLOAT64)), 0), 2) as cpa_usd
FROM `hulken.ads_data.tiktok_ads_reports_daily`
GROUP BY mois
ORDER BY mois;


-- =====================================================
-- EXPORT 4: Top 50 Ads par conversions (derniers 6 mois)
-- =====================================================
SELECT
  JSON_VALUE(metrics, '$.ad_name') as ad_name,
  JSON_VALUE(metrics, '$.campaign_name') as campaign_name,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)), 2) as spend_usd,
  SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS INT64)) as impressions,
  SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS INT64)) as clicks,
  SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS INT64)) as conversions,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.clicks') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.impressions') AS FLOAT64)), 0) * 100, 2) as ctr_pct,
  ROUND(SUM(CAST(JSON_VALUE(metrics, '$.spend') AS FLOAT64)) /
        NULLIF(SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS FLOAT64)), 0), 2) as cpa_usd
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE stat_time_day >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
GROUP BY ad_name, campaign_name
HAVING SUM(CAST(JSON_VALUE(metrics, '$.conversion') AS INT64)) > 0
ORDER BY conversions DESC
LIMIT 50;
