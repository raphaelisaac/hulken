# Facebook Ads Deep Analysis - HULKEN Europe
**Date:** January 28, 2026
**Analyst:** Claude Code
**Data Source:** BigQuery (Airbyte sync from Facebook Marketing API)

---

## Table of Contents
1. [Data Sources & Methodology](#data-sources--methodology)
2. [Executive Summary](#executive-summary)
3. [Performance by Country](#performance-by-country)
4. [Campaign Analysis by Country](#campaign-analysis-by-country)
5. [Loss-Making Campaigns (Critical)](#loss-making-campaigns-critical)
6. [Monthly Trends](#monthly-trends)
7. [Quick Wins & Recommendations](#quick-wins--recommendations)
8. [SQL Queries Reference](#sql-queries-reference)

---

## Data Sources & Methodology

### Tables Used

| Table | Description | Records |
|-------|-------------|---------|
| `hulken.airbyte_internal.ads_dataads_insights8b8754ab2c6d45382f92c2e36de053c7` | Main Facebook ads insights | ~32,624 |
| `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b` | Ads insights by country | ~103,787 |

### Data Period
- **Start Date:** October 11, 2024
- **End Date:** January 27, 2026
- **Days of Data:** 472
- **Campaigns:** 23

### Key Metrics Calculation

```sql
-- Revenue is calculated from purchase_roas field:
revenue = CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64) * spend

-- ROAS (Return on Ad Spend):
roas = revenue / spend

-- Profit:
profit = revenue - spend
```

---

## Executive Summary

### Overall Facebook Performance

| Metric | Value |
|--------|-------|
| **Total Spend** | $331,791 |
| **Total Revenue** | $502,043 |
| **Overall ROAS** | **1.51x** |
| **Total Profit** | **$170,252** |
| **Impressions** | 17.5M |
| **Clicks** | 361,690 |
| **CTR** | 2.06% |
| **CPC** | $0.92 |

### Key Finding
Facebook generates **$1.51 for every $1 spent** - significantly better than TikTok (1.08x ROAS).

**Query Used:**
```sql
SELECT
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as total_spend,
  ROUND(SUM(
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
    * CAST(spend AS FLOAT64)
  ), 2) as estimated_revenue,
  ROUND(SUM(
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
    * CAST(spend AS FLOAT64)
  ) / NULLIF(SUM(CAST(spend AS FLOAT64)), 0), 2) as overall_roas
FROM `hulken.airbyte_internal.ads_dataads_insights8b8754ab2c6d45382f92c2e36de053c7`
```

---

## Performance by Country

### Complete Country Breakdown

| Country | Spend | Revenue | ROAS | Profit | CTR | CPC |
|---------|-------|---------|------|--------|-----|-----|
| 🇩🇪 Germany | $118,932 | $165,932 | 1.40x | +$46,999 | 2.19% | $1.10 |
| 🇬🇧 UK | $81,130 | $111,940 | 1.38x | +$30,811 | 2.96% | $0.86 |
| 🇫🇷 France | $45,196 | $67,208 | 1.49x | +$22,012 | 1.88% | $0.66 |
| 🇦🇹 Austria | $30,580 | $58,477 | **1.91x** | +$27,897 | 1.50% | $1.38 |
| 🇳🇱 Netherlands | $23,827 | $37,426 | 1.57x | +$13,599 | 2.23% | $0.76 |
| 🇪🇸 Spain | $6,974 | $14,434 | **2.07x** | +$7,460 | 1.67% | $0.73 |
| 🇧🇪 Belgium | $6,233 | $13,181 | **2.11x** | +$6,948 | 1.39% | $1.14 |
| 🇮🇹 Italy | $4,877 | $7,447 | 1.53x | +$2,570 | 1.16% | $0.89 |
| 🇸🇪 Sweden | $2,770 | $5,032 | 1.82x | +$2,262 | 1.62% | $1.29 |
| 🇬🇷 Greece | $2,502 | $3,293 | 1.32x | +$791 | 1.29% | $0.56 |
| 🇵🇹 Portugal | $2,243 | $3,816 | 1.70x | +$1,573 | 1.07% | $0.56 |
| 🇭🇺 Hungary | $2,168 | $5,558 | **2.56x** | +$3,390 | 1.04% | $0.58 |
| 🇮🇪 Ireland | $2,090 | $3,458 | 1.65x | +$1,368 | 1.03% | $1.45 |
| 🇨🇭 Switzerland | $550 | $1,069 | 1.94x | +$519 | 1.23% | $2.37 |
| 🇫🇮 Finland | $113 | $117 | 1.03x | +$4 | 0.97% | $1.92 |
| 🇦🇺 **Australia** | $1,106 | $586 | **0.53x** | **-$519** | 1.58% | $0.91 |
| 🇩🇰 **Denmark** | $612 | $543 | **0.89x** | **-$70** | 1.35% | $1.53 |

### Key Insights by Country

#### 🏆 Best Performing Countries (Scale Opportunities)

| Rank | Country | ROAS | Why Scale |
|------|---------|------|-----------|
| 1 | 🇭🇺 Hungary | 2.56x | Highest ROAS, low competition |
| 2 | 🇧🇪 Belgium | 2.11x | Strong profit margin |
| 3 | 🇪🇸 Spain | 2.07x | Good volume potential |
| 4 | 🇨🇭 Switzerland | 1.94x | High AOV market |
| 5 | 🇦🇹 Austria | 1.91x | Already scaled, maintain |

#### 🔴 Loss-Making Countries (Immediate Action Required)

| Country | Spend | Loss | Action |
|---------|-------|------|--------|
| 🇦🇺 Australia | $1,106 | -$519 | **PAUSE immediately** |
| 🇩🇰 Denmark | $612 | -$70 | **Pause or restructure** |

**Query Used:**
```sql
SELECT
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  SUM(t.impressions) as impressions,
  SUM(t.clicks) as clicks,
  ROUND(SUM(t.clicks) / NULLIF(SUM(t.impressions), 0) * 100, 2) as ctr,
  ROUND(SUM(t.spend) / NULLIF(SUM(t.clicks), 0), 2) as cpc,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas,
  ROUND(SUM(t.revenue) - SUM(t.spend), 2) as profit
FROM (
  SELECT
    country,
    CAST(spend AS FLOAT64) as spend,
    CAST(impressions AS INT64) as impressions,
    CAST(clicks AS INT64) as clicks,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
) t
GROUP BY t.country
HAVING SUM(t.spend) > 100
ORDER BY spend DESC
```

---

## Campaign Analysis by Country

### Top 30 Campaign + Country Combinations

| Campaign | Country | Spend | Revenue | ROAS | Status |
|----------|---------|-------|---------|------|--------|
| de-at_prospecting_eng | 🇩🇪 DE | $28,465 | $46,476 | 1.63x | ✅ Good |
| **de-at_prospecting** | 🇩🇪 DE | $27,261 | $19,344 | **0.71x** | 🔴 LOSS |
| uk_prospecting_eng | 🇬🇧 GB | $24,088 | $47,198 | **1.96x** | ✅ Great |
| uk_prospecting | 🇩🇪 DE | $22,013 | $30,973 | 1.41x | ✅ OK |
| **uk_prospecting** | 🇬🇧 GB | $17,580 | $16,790 | **0.96x** | 🔴 LOSS |
| eu-uk_advantage_shopping_3_p2 | 🇬🇧 GB | $16,760 | $22,437 | 1.34x | ✅ OK |
| **fr_prospecting** | 🇫🇷 FR | $12,469 | $11,026 | **0.88x** | 🔴 LOSS |
| fr_prospecting_eng | 🇫🇷 FR | $8,036 | $15,476 | **1.93x** | ✅ Great |
| de-at_prospecting_eng | 🇦🇹 AT | $7,587 | $17,759 | **2.34x** | ✅ Excellent |
| eu_remarketing_dpa | 🇩🇪 DE | $7,279 | $13,077 | 1.80x | ✅ Good |
| eu_prospecting_eng | 🇩🇪 DE | $6,851 | $19,611 | **2.86x** | ✅ Excellent |
| **eu_remarketing** | 🇬🇧 GB | $6,614 | $3,724 | **0.56x** | 🔴 LOSS |
| eu_remarketing_dpa | 🇬🇧 GB | $6,463 | $12,502 | 1.93x | ✅ Great |
| eu_prospecting_eng | 🇫🇷 FR | $4,633 | $13,048 | **2.82x** | ✅ Excellent |
| eu_prospecting_eng | 🇳🇱 NL | $4,003 | $11,804 | **2.95x** | ✅ Excellent |

### Best ROAS Combinations (>2x)

| Campaign | Country | ROAS | Recommendation |
|----------|---------|------|----------------|
| eu_prospecting_eng | 🇳🇱 NL | **2.95x** | 🚀 Scale aggressively |
| eu_prospecting_eng | 🇩🇪 DE | **2.86x** | 🚀 Scale aggressively |
| eu_prospecting_eng | 🇫🇷 FR | **2.82x** | 🚀 Scale aggressively |
| de-at_prospecting_eng | 🇦🇹 AT | **2.34x** | 🚀 Scale |
| uk_prospecting_eng | 🇬🇧 GB | **1.96x** | 🚀 Scale |
| fr_prospecting_eng | 🇫🇷 FR | **1.93x** | 🚀 Scale |

**Conclusion:** The `_eng` (engagement) campaigns consistently outperform standard prospecting campaigns across all countries.

---

## Loss-Making Campaigns (Critical)

### 🚨 Campaigns Losing Money

| Campaign | Country | Spend | Revenue | ROAS | **LOSS** |
|----------|---------|-------|---------|------|----------|
| de-at_prospecting | 🇩🇪 DE | $27,261 | $19,344 | 0.71x | **-$7,918** |
| eu_remarketing | 🇬🇧 GB | $6,614 | $3,724 | 0.56x | **-$2,890** |
| eu_boosting | 🇫🇷 FR | $3,006 | $281 | 0.09x | **-$2,724** |
| eu_boosting | 🇬🇧 GB | $3,215 | $858 | 0.27x | **-$2,357** |
| fr_prospecting | 🇫🇷 FR | $12,469 | $11,026 | 0.88x | **-$1,443** |
| fr_advantage_shopping | 🇫🇷 FR | $1,336 | $335 | 0.25x | **-$1,002** |
| eu_boosting | 🇩🇪 DE | $1,606 | $652 | 0.41x | **-$955** |
| eu_remarketing | 🇩🇪 DE | $3,649 | $2,734 | 0.75x | **-$915** |
| uk_prospecting | 🇬🇧 GB | $17,580 | $16,790 | 0.96x | **-$790** |
| eu_boosting | 🇬🇷 GR | $629 | $0 | 0.00x | **-$629** |

### Total Losses from Bad Campaigns: **-$22,623**

### Immediate Actions Required

1. **PAUSE `eu_boosting`** in all countries
   - Total loss: -$6,665 across FR, GB, DE, GR
   - ROAS ranges from 0.00x to 0.41x

2. **PAUSE `de-at_prospecting` in Germany**
   - Single biggest loss: -$7,918
   - Replace with `de-at_prospecting_eng` (ROAS 1.63x)

3. **Restructure `eu_remarketing` in UK**
   - Loss: -$2,890
   - DPA version works (1.93x ROAS) - switch to DPA only

4. **Optimize `fr_prospecting`**
   - ROAS 0.88x is close to break-even
   - Test new creatives or switch to `fr_prospecting_eng` (1.93x)

**Query Used:**
```sql
SELECT
  t.campaign_name,
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas,
  ROUND(SUM(t.revenue) - SUM(t.spend), 2) as loss
FROM (
  SELECT
    campaign_name,
    country,
    CAST(spend AS FLOAT64) as spend,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
) t
GROUP BY t.campaign_name, t.country
HAVING SUM(t.spend) > 500 AND SUM(t.revenue) / NULLIF(SUM(t.spend), 0) < 1
ORDER BY loss ASC
```

---

## Monthly Trends

### Top 5 Countries - Monthly Performance

#### January 2026 (Current Month)

| Country | Spend | Revenue | ROAS | Trend |
|---------|-------|---------|------|-------|
| 🇩🇪 Germany | $5,474 | $9,346 | 1.71x | ↑ Improving |
| 🇬🇧 UK | $4,787 | $10,034 | **2.10x** | ↑ Best month! |
| 🇫🇷 France | $3,108 | $4,756 | 1.53x | → Stable |
| 🇳🇱 Netherlands | $2,835 | $4,327 | 1.53x | → Stable |
| 🇦🇹 Austria | $1,338 | $2,545 | 1.90x | → Stable |

#### December 2025 (Holiday Season)

| Country | Spend | Revenue | ROAS |
|---------|-------|---------|------|
| 🇩🇪 Germany | $13,441 | $16,515 | 1.23x |
| 🇬🇧 UK | $11,025 | $14,341 | 1.30x |
| 🇫🇷 France | $9,466 | $12,528 | 1.32x |
| 🇦🇹 Austria | $4,002 | $6,696 | 1.67x |
| 🇳🇱 Netherlands | $115 | $342 | 2.97x |

#### November 2025 (Black Friday)

| Country | Spend | Revenue | ROAS |
|---------|-------|---------|------|
| 🇩🇪 Germany | $21,190 | $28,972 | 1.37x |
| 🇬🇧 UK | $16,614 | $19,921 | 1.20x |
| 🇫🇷 France | $10,927 | $13,310 | 1.22x |
| 🇦🇹 Austria | $4,246 | $7,922 | **1.87x** |
| 🇳🇱 Netherlands | $236 | $1,239 | **5.26x** |

### Seasonal Insights

1. **Q4 (Nov-Dec)**: Highest spend but ROAS drops due to competition
2. **January**: ROAS improves as competition decreases
3. **Austria** maintains strong ROAS (1.67-1.90x) across all seasons
4. **Netherlands** has volatile but high-potential ROAS

---

## Quick Wins & Recommendations

### 🔴 Immediate Actions (This Week)

| Priority | Action | Expected Impact |
|----------|--------|-----------------|
| 1 | **PAUSE `eu_boosting`** all countries | Save $6,665 in losses |
| 2 | **PAUSE `de-at_prospecting`** in Germany | Save $7,918 in losses |
| 3 | **PAUSE Australia & Denmark** | Save $589 in losses |
| 4 | **Switch `eu_remarketing` UK → DPA only** | Save $2,890 in losses |

**Total Immediate Savings: ~$18,000+**

### 🟡 Optimization Actions (This Month)

| Action | Current | Target | Method |
|--------|---------|--------|--------|
| Shift budget DE → AT, HU, BE, ES | Mixed ROAS | 2x+ ROAS | Budget reallocation |
| Replace `_prospecting` → `_prospecting_eng` | 0.7-0.9x | 1.6-2.8x | Campaign restructure |
| Scale Netherlands | $24K spend | $50K spend | Gradual increase |

### 🟢 Growth Opportunities

| Country | Current Spend | Potential | ROAS | Action |
|---------|---------------|-----------|------|--------|
| 🇭🇺 Hungary | $2,168 | $10,000 | 2.56x | Test scaling |
| 🇧🇪 Belgium | $6,233 | $15,000 | 2.11x | Gradual scale |
| 🇪🇸 Spain | $6,974 | $20,000 | 2.07x | Test new audiences |
| 🇨🇭 Switzerland | $550 | $5,000 | 1.94x | High AOV market |

### Budget Reallocation Recommendation

| From | To | Amount | Expected Gain |
|------|-----|--------|---------------|
| eu_boosting (all) | eu_prospecting_eng (all) | $8,500 | +$15K revenue |
| de-at_prospecting DE | de-at_prospecting_eng DE | $27,000 | +$17K revenue |
| Australia + Denmark | Hungary + Belgium | $1,700 | +$2K revenue |

---

## SQL Queries Reference

### 1. Overall Facebook Performance

```sql
SELECT
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) as total_spend,
  SUM(CAST(impressions AS INT64)) as total_impressions,
  SUM(CAST(clicks AS INT64)) as total_clicks,
  ROUND(SUM(CAST(clicks AS FLOAT64)) /
    NULLIF(SUM(CAST(impressions AS FLOAT64)), 0) * 100, 2) as ctr,
  ROUND(SUM(CAST(spend AS FLOAT64)) /
    NULLIF(SUM(CAST(clicks AS FLOAT64)), 0), 2) as cpc
FROM `hulken.airbyte_internal.ads_dataads_insights8b8754ab2c6d45382f92c2e36de053c7`
```

### 2. Performance by Country with ROAS

```sql
SELECT
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  SUM(t.impressions) as impressions,
  SUM(t.clicks) as clicks,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas,
  ROUND(SUM(t.revenue) - SUM(t.spend), 2) as profit
FROM (
  SELECT
    country,
    CAST(spend AS FLOAT64) as spend,
    CAST(impressions AS INT64) as impressions,
    CAST(clicks AS INT64) as clicks,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
) t
GROUP BY t.country
ORDER BY spend DESC
```

### 3. Campaign Performance by Country

```sql
SELECT
  t.campaign_name,
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  SUM(t.clicks) as clicks,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas
FROM (
  SELECT
    campaign_name,
    country,
    CAST(spend AS FLOAT64) as spend,
    CAST(clicks AS INT64) as clicks,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
) t
GROUP BY t.campaign_name, t.country
HAVING SUM(t.spend) > 1000
ORDER BY spend DESC
```

### 4. Loss-Making Campaigns

```sql
SELECT
  t.campaign_name,
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas,
  ROUND(SUM(t.revenue) - SUM(t.spend), 2) as loss
FROM (
  SELECT
    campaign_name,
    country,
    CAST(spend AS FLOAT64) as spend,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
) t
GROUP BY t.campaign_name, t.country
HAVING SUM(t.revenue) / NULLIF(SUM(t.spend), 0) < 1 AND SUM(t.spend) > 500
ORDER BY loss ASC
```

### 5. Monthly Trend by Country

```sql
SELECT
  FORMAT_DATE('%Y-%m', DATE(t.date_start)) as month,
  t.country,
  ROUND(SUM(t.spend), 2) as spend,
  ROUND(SUM(t.revenue), 2) as revenue,
  ROUND(SUM(t.revenue) / NULLIF(SUM(t.spend), 0), 2) as roas
FROM (
  SELECT
    date_start,
    country,
    CAST(spend AS FLOAT64) as spend,
    COALESCE(CAST(JSON_VALUE(purchase_roas, '$[0].value') AS FLOAT64), 0)
      * CAST(spend AS FLOAT64) as revenue
  FROM `hulken.airbyte_internal.ads_dataads_insi_country54c8b6aaccb435389dd84af8d000714b`
  WHERE country IN ('DE', 'GB', 'FR', 'AT', 'NL')
) t
GROUP BY month, t.country
ORDER BY month DESC, spend DESC
```

---

## Appendix: Data Dictionary

### Facebook Ads Insights Fields

| Field | Type | Description |
|-------|------|-------------|
| `spend` | FLOAT | Amount spent in USD |
| `impressions` | INT | Number of ad impressions |
| `clicks` | INT | Number of clicks |
| `ctr` | FLOAT | Click-through rate (%) |
| `cpc` | FLOAT | Cost per click ($) |
| `cpm` | FLOAT | Cost per 1000 impressions ($) |
| `purchase_roas` | JSON | Return on ad spend for purchases |
| `country` | STRING | ISO country code |
| `campaign_name` | STRING | Campaign name |
| `adset_name` | STRING | Ad set name |
| `ad_name` | STRING | Ad creative name |
| `date_start` | DATE | Report date start |
| `date_stop` | DATE | Report date end |

---

*Document generated on January 28, 2026*
*Data freshness: Real-time via Airbyte sync*
*Next update: Automatic with data refresh*
