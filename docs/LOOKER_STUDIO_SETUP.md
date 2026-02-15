# Looker Studio - Setup & Dashboard Creation

**Date:** 2026-02-15
**Objectif:** Créer des dashboards professionnels connectés à BigQuery pour reporting automatisé

---

## 🎯 Pourquoi Looker Studio?

| PowerPoint (Statique) | Looker Studio (Dynamique) |
|----------------------|---------------------------|
| ❌ Données figées | ✅ Données en temps réel |
| ❌ Mise à jour manuelle | ✅ Auto-refresh quotidien |
| ❌ Copier-coller depuis BigQuery | ✅ Connexion directe BigQuery |
| ✅ Éditable | ✅ Éditable |
| ❌ Partage limité | ✅ Partage par lien |
| ❌ Pas de drill-down | ✅ Filtres interactifs |

**Bonus:** Tu peux toujours **exporter en PDF** ou **copier dans PowerPoint** si besoin!

---

## 🚀 Étape 1: Accéder à Looker Studio

1. Aller sur: https://lookerstudio.google.com
2. Se connecter avec ton compte Google lié au projet `hulken`
3. Cliquer **"Create"** → **"Report"**

---

## 🔌 Étape 2: Connecter BigQuery

### A. Première connexion

1. Dans le nouveau rapport, cliquer **"Add data"**
2. Chercher **"BigQuery"** dans les connecteurs
3. Sélectionner **"BigQuery"** (par Google)
4. Autoriser l'accès à BigQuery

### B. Sélectionner les tables

1. **Project:** `hulken`
2. **Dataset:** `ads_data`
3. **Table:** Commencer avec `marketing_unified`
4. Cliquer **"Add"**

### C. Ajouter d'autres tables

Pour créer des graphiques multi-sources, répéter pour:
- `shopify_unified`
- `facebook_unified`
- `tiktok_unified`
- `google_ads_unified`

---

## 📊 Étape 3: Visualiser les Tables dans BigQuery

### Option 1: BigQuery Console Web

1. Aller sur: https://console.cloud.google.com/bigquery
2. Sélectionner le projet **`hulken`**
3. Dans le panneau de gauche, développer:
   ```
   hulken
   └── ads_data
       ├── marketing_unified
       ├── shopify_unified
       ├── facebook_unified
       ├── tiktok_unified
       └── google_ads_unified
   ```
4. Cliquer sur une table pour voir:
   - **Schema** (colonnes et types)
   - **Details** (taille, nombre de lignes)
   - **Preview** (premières lignes)

### Option 2: Requête SQL

```sql
-- Voir toutes les tables dans ads_data
SELECT
  table_id AS table_name,
  row_count,
  ROUND(size_bytes / 1024 / 1024, 2) AS size_mb,
  TIMESTAMP_MILLIS(creation_time) AS created_at
FROM `hulken.ads_data.__TABLES__`
ORDER BY row_count DESC;
```

### Option 3: Exploration rapide

```sql
-- Preview marketing_unified
SELECT *
FROM `hulken.ads_data.marketing_unified`
ORDER BY date DESC
LIMIT 100;
```

---

## 🎨 Étape 4: Créer les Dashboards

Je vais te donner les requêtes SQL pour chaque section de ton rapport.

### Dashboard 1: Executive Summary

**Source de données:** Créer une **Custom Query** dans Looker Studio

```sql
-- KPIs mensuels avec YoY
WITH current_month AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,
    SUM(revenue) AS gross_revenue,
    SUM(net_revenue) AS net_revenue,
    SUM(ad_spend) AS marketing_spend,
    SUM(orders) AS orders
  FROM `hulken.ads_data.marketing_unified`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH)
  GROUP BY month
),

last_year_month AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,
    SUM(revenue) AS gross_revenue,
    SUM(net_revenue) AS net_revenue,
    SUM(ad_spend) AS marketing_spend,
    SUM(orders) AS orders
  FROM `hulken.ads_data.marketing_unified`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), MONTH)
  GROUP BY month
)

SELECT
  'Gross Revenue' AS metric,
  c.gross_revenue AS current_value,
  l.gross_revenue AS last_year_value,
  SAFE_DIVIDE(c.gross_revenue - l.gross_revenue, l.gross_revenue) * 100 AS yoy_change_percent
FROM current_month c
CROSS JOIN last_year_month l

UNION ALL

SELECT
  'Net Revenue',
  c.net_revenue,
  l.net_revenue,
  SAFE_DIVIDE(c.net_revenue - l.net_revenue, l.net_revenue) * 100
FROM current_month c
CROSS JOIN last_year_month l

UNION ALL

SELECT
  'Marketing Spend',
  c.marketing_spend,
  l.marketing_spend,
  SAFE_DIVIDE(c.marketing_spend - l.marketing_spend, l.marketing_spend) * 100
FROM current_month c
CROSS JOIN last_year_month l

UNION ALL

SELECT
  'Orders',
  c.orders,
  l.orders,
  SAFE_DIVIDE(c.orders - l.orders, l.orders) * 100
FROM current_month c
CROSS JOIN last_year_month l;
```

**Visualisation dans Looker:**
- **Type:** Scorecard
- **Metric:** `current_value`
- **Comparison:** `yoy_change_percent`

---

### Dashboard 2: Marketing Efficiency

```sql
-- Total NR MER vs Contribution Margin
SELECT
  DATE_TRUNC(date, MONTH) AS month,
  SUM(net_revenue) AS net_revenue,
  SUM(ad_spend) AS ad_spend,
  SAFE_DIVIDE(SUM(net_revenue), SUM(ad_spend)) AS mer,
  SUM(net_revenue) - SUM(ad_spend) AS contribution_margin,
  SAFE_DIVIDE(SUM(ad_spend), SUM(net_revenue)) * 100 AS marketing_pct_of_revenue
FROM `hulken.ads_data.marketing_unified`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH)
GROUP BY month
ORDER BY month;
```

**Visualisation:**
- **Type:** Combo Chart
- **Bar:** `contribution_margin`
- **Line:** `mer`
- **X-axis:** `month`

---

### Dashboard 3: Sitewide Overview (Shopify)

**Note:** Tu dois d'abord créer une vue qui agrège par jour/mois depuis shopify_unified

```sql
CREATE OR REPLACE VIEW `hulken.ads_data.shopify_daily_metrics` AS

SELECT
  order_date AS date,

  -- Orders & Revenue
  COUNT(DISTINCT order_id) AS orders,
  SUM(order_value) AS gross_revenue,
  SUM(order_net_value) AS net_revenue,
  AVG(order_value) AS aov,

  -- Customers
  COUNT(DISTINCT customer_id) AS unique_customers,
  SAFE_DIVIDE(
    COUNTIF(customer_order_count_shopify > 1),
    COUNT(DISTINCT customer_id)
  ) * 100 AS returning_customer_pct,

  -- Attribution
  COUNTIF(is_cancelled = TRUE) AS cancelled_orders,
  COUNTIF(has_refund = TRUE) AS refunded_orders

FROM `hulken.ads_data.shopify_unified`
WHERE order_date IS NOT NULL
GROUP BY order_date;
```

Ensuite dans Looker:

```sql
-- Sitewide KPIs (dernier mois)
WITH current_month AS (
  SELECT
    SUM(orders) AS orders,
    SUM(net_revenue) AS net_revenue,
    AVG(aov) AS aov,
    SUM(unique_customers) AS customers,
    AVG(returning_customer_pct) AS returning_pct
  FROM `hulken.ads_data.shopify_daily_metrics`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH)
),

last_year AS (
  SELECT
    SUM(orders) AS orders,
    SUM(net_revenue) AS net_revenue,
    AVG(aov) AS aov,
    SUM(unique_customers) AS customers,
    AVG(returning_customer_pct) AS returning_pct
  FROM `hulken.ads_data.shopify_daily_metrics`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), MONTH)
)

SELECT
  'Orders' AS metric,
  c.orders AS current_value,
  SAFE_DIVIDE(c.orders - l.orders, l.orders) * 100 AS yoy_change
FROM current_month c, last_year l

UNION ALL

SELECT 'Net Revenue', c.net_revenue, SAFE_DIVIDE(c.net_revenue - l.net_revenue, l.net_revenue) * 100
FROM current_month c, last_year l

UNION ALL

SELECT 'AOV', c.aov, SAFE_DIVIDE(c.aov - l.aov, l.aov) * 100
FROM current_month c, last_year l

UNION ALL

SELECT 'Unique Customers', c.customers, SAFE_DIVIDE(c.customers - l.customers, l.customers) * 100
FROM current_month c, last_year l

UNION ALL

SELECT 'Returning %', c.returning_pct, SAFE_DIVIDE(c.returning_pct - l.returning_pct, l.returning_pct) * 100
FROM current_month c, last_year l;
```

---

### Dashboard 4: Traffic & Sales Trends

**Note:** Pour avoir Sessions et Users, tu dois connecter Google Analytics 4 à BigQuery ou utiliser Shopify Analytics.

Si tu n'as pas GA4 connecté, on peut utiliser orders comme proxy:

```sql
-- Orders vs Revenue trend
SELECT
  DATE_TRUNC(date, MONTH) AS month,
  SUM(orders) AS total_orders,
  SUM(net_revenue) AS net_revenue,
  SUM(gross_revenue) AS gross_revenue
FROM `hulken.ads_data.shopify_daily_metrics`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH)
GROUP BY month
ORDER BY month;
```

---

### Dashboard 5: Paid Channel Mix

```sql
-- PPC Channel Performance
SELECT
  channel,
  SUM(ad_spend) AS spend,
  SUM(revenue) AS revenue,
  SUM(orders) AS orders,
  AVG(avg_order_value) AS aov,
  SAFE_DIVIDE(SUM(ad_spend), SUM(orders)) AS cpa,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas
FROM `hulken.ads_data.marketing_unified`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)
  AND channel IN ('facebook', 'google', 'tiktok')
GROUP BY channel
ORDER BY spend DESC;
```

**Visualisation:**
- **Pie Chart** pour spend distribution
- **Table** pour les métriques détaillées

---

### Dashboard 6: Top Products

```sql
-- Top 20 produits par revenue
WITH product_performance AS (
  SELECT
    product_titles,
    SUM(items_total_original) AS gross_revenue,
    SUM(items_total_original - COALESCE(order_discounts, 0)) AS net_revenue,
    SUM(total_quantity) AS units_sold
  FROM `hulken.ads_data.shopify_unified`
  WHERE order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)
    AND product_titles IS NOT NULL
  GROUP BY product_titles
)

SELECT
  product_titles AS product_name,
  gross_revenue,
  net_revenue,
  units_sold,
  SAFE_DIVIDE(net_revenue, units_sold) AS avg_price_per_unit
FROM product_performance
ORDER BY net_revenue DESC
LIMIT 20;
```

---

## 🎨 Design du Dashboard Looker

### Layout Recommandé

**Page 1: Executive Summary**
- 4 Scorecards en haut (Revenue, Orders, AOV, ROAS)
- 1 graphique combo (Spend vs Revenue trend)
- 1 table (Top channels)

**Page 2: Marketing Efficiency**
- 2 graphiques combo (MER trends, Contribution trends)
- 1 pie chart (Spend distribution)
- 1 table (Channel performance)

**Page 3: Shopify Performance**
- 6 Scorecards (Orders, Revenue, AOV, CVR, New customers, Returning %)
- 2 Line charts (Traffic trend, Sales trend)
- 1 Bar chart (Top products)

**Page 4: Paid Ads Deep Dive**
- 1 Table (Facebook campaigns)
- 1 Table (Google campaigns)
- 1 Table (TikTok campaigns)
- Filters: Date range, Campaign status

---

## 🎨 Styling Tips

### Colors (Brand cohesion)
- **Primary:** #4285F4 (Google Blue)
- **Success:** #34A853 (Green for positive growth)
- **Warning:** #FBBC04 (Yellow for attention)
- **Danger:** #EA4335 (Red for negative)

### Fonts
- **Headers:** Roboto Bold, 24px
- **Metrics:** Roboto Medium, 48px
- **Labels:** Roboto Regular, 12px

### Charts
- **Bar charts:** Pour comparaisons (channels, products)
- **Line charts:** Pour trends temporels
- **Scorecards:** Pour KPIs clés
- **Tables:** Pour details & drill-down

---

## 📤 Export vers PowerPoint

### Option 1: Download as PDF
1. Dans Looker Studio, cliquer **"Download report"**
2. Sélectionner **"PDF - current page"** ou **"PDF - all pages"**
3. Ouvrir le PDF dans PowerPoint (Insert → Pictures)

### Option 2: Screenshot
1. Utiliser Cmd+Shift+4 (Mac) ou Snipping Tool (Windows)
2. Copier les graphiques
3. Coller dans PowerPoint

### Option 3: Embed Link
1. Cliquer **"Share"** → **"Get report link"**
2. Dans PowerPoint, Insert → Link
3. Les stakeholders peuvent voir le live dashboard

---

## 🔄 Automatisation & Refresh

### Auto-refresh
- Looker Studio refresh automatiquement les données de BigQuery **toutes les 12h**
- Pour forcer un refresh: Cliquer **"Refresh data"** (icône en haut à droite)

### Scheduled Delivery
1. Dans Looker, cliquer **"Schedule delivery"**
2. Choisir:
   - **Frequency:** Daily, Weekly, Monthly
   - **Format:** PDF ou Link
   - **Recipients:** Emails
3. Le rapport sera envoyé automatiquement!

---

## 🚨 Troubleshooting

### "No data to display"
**Cause:** La requête ne retourne rien

**Solutions:**
- Vérifier le filtre de dates (peut-être aucune donnée pour cette période)
- Tester la requête dans BigQuery Console d'abord
- Vérifier que la table existe et a des données

### "BigQuery error: Invalid field name"
**Cause:** Le nom de colonne n'existe pas dans la table

**Solutions:**
- Vérifier le schéma de la table dans BigQuery
- Corriger le nom du champ dans la requête

### "Timeout exceeded"
**Cause:** La requête est trop lente (>30 secondes)

**Solutions:**
- Limiter la période (ex: dernier mois au lieu de tout l'historique)
- Créer une vue matérialisée dans BigQuery
- Optimiser la requête (éviter les JOINs multiples)

---

## 📚 Ressources

- **Looker Studio Docs:** https://support.google.com/looker-studio
- **BigQuery SQL Reference:** https://cloud.google.com/bigquery/docs/reference/standard-sql
- **Looker Templates Gallery:** https://lookerstudio.google.com/gallery

---

## 🎉 Quick Start

**Pour commencer MAINTENANT:**

1. Va sur: https://lookerstudio.google.com
2. Clique **"Create"** → **"Report"**
3. Ajoute la source **BigQuery** → `hulken.ads_data.marketing_unified`
4. Créer un Scorecard avec:
   - **Metric:** `SUM(revenue)`
   - **Date range:** Last 30 days
5. Voilà! Ton premier KPI est créé 🎉

Ensuite, ajoute d'autres graphiques en copiant les requêtes SQL ci-dessus.

