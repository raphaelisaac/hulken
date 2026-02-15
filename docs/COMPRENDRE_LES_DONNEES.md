# Comprendre les Données - Guide Complet 📖

**Date:** 2026-02-15

---

## 🤔 Problème: Pourcentages Sans Contexte

### Exemple du Problème

Dans le rapport tu vois:
```
Revenue: $125,000 (+15.2%) ← Mais 15% vs QUOI? Quel mois? Quelle année?
```

**C'est confus!** ❌

---

## ✅ Solution: Labels de Période Clairs

### Dans BigQuery

**Requête MAUVAISE (ambiguë):**
```sql
SELECT
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(revenue) - LAG(SUM(revenue)) OVER (), LAG(SUM(revenue)) OVER ()) * 100 AS growth_pct
FROM marketing_unified;
```

**Résultat:** `revenue: $125,000, growth_pct: 15.2%` ← Vs quoi? 🤷

---

**Requête BONNE (claire):**
```sql
WITH current_month AS (
  SELECT
    SUM(revenue) AS revenue,
    'February 2026' AS period_label
  FROM `hulken.ads_data.marketing_unified`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH)
),

last_year_same_month AS (
  SELECT
    SUM(revenue) AS revenue,
    'February 2025' AS period_label
  FROM `hulken.ads_data.marketing_unified`
  WHERE DATE_TRUNC(date, MONTH) = DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), MONTH)
)

SELECT
  -- Current period
  c.period_label AS current_period,
  c.revenue AS current_revenue,

  -- Comparison period
  l.period_label AS comparison_period,
  l.revenue AS last_year_revenue,

  -- Growth (clearly labeled!)
  SAFE_DIVIDE(c.revenue - l.revenue, l.revenue) * 100 AS yoy_growth_pct,
  'YoY' AS growth_type

FROM current_month c
CROSS JOIN last_year_same_month l;
```

**Résultat (clair!):**
```
current_period    | current_revenue | comparison_period | last_year_revenue | yoy_growth_pct | growth_type
February 2026     | $125,000        | February 2025     | $108,695          | 15.2%          | YoY
```

**Maintenant c'est CLAIR!** ✅

---

### Dans Looker Studio

**TOUJOURS ajouter ces éléments:**

1. **Titre du scorecard:**
   ```
   Revenue - February 2026
   (vs February 2025)
   ```

2. **Comparison label:**
   - Dans Scorecard → **Style** → **Comparison label**
   - Écrire: "vs Feb 2025"

3. **Date range picker:**
   - Ajouter un contrôle de date en haut du dashboard
   - **Add a control** → **Date range control**
   - Placer en haut à gauche

4. **Texte explicatif:**
   - Ajouter une text box:
     ```
     "All metrics compare current period vs same period last year (YoY)"
     ```

---

### Dans PowerPoint

**Chaque slide DOIT avoir:**

1. **Header avec période:**
   ```
   Executive Summary - February 2026
   Comparison: February 2025 (YoY)
   ```

2. **Labels dans les KPIs:**
   ```
   Gross Revenue (Feb 2026)
   $3,046,383
   ↑ 15.2% vs Feb 2025
   ```

3. **Footer avec date de génération:**
   ```
   Generated: 2026-02-15 | Data as of: 2026-02-14 | Source: BigQuery hulken.ads_data
   ```

---

## 🔢 Problème: Valeurs à 0 - Qu'est-ce Que Ça Veut Dire?

### Cas 1: Vente à $0 (Order Value = 0)

#### Possibilités:

**A. Commande Test (Normal ✅)**
```sql
SELECT
  order_id,
  order_value,
  order_tags,
  source_name
FROM shopify_unified
WHERE order_value = 0
  AND (
    order_tags LIKE '%test%'
    OR source_name = 'shopify_draft_order'
  );
```

**Explication:** Commandes de test créées manuellement. **Normal!**

---

**B. Commande 100% Discount (Normal ✅)**
```sql
SELECT
  order_id,
  order_value,
  order_discounts,
  order_subtotal
FROM shopify_unified
WHERE order_value = 0
  AND order_discounts >= order_subtotal;
```

**Explication:** Client a eu un coupon 100% off. **Normal!**

---

**C. Commande Gratuite (Échantillon) (Normal ✅)**
```sql
SELECT
  order_id,
  order_value,
  product_titles
FROM shopify_unified
WHERE order_value = 0
  AND (
    product_titles LIKE '%sample%'
    OR product_titles LIKE '%free%'
  );
```

**Explication:** Échantillons gratuits envoyés. **Normal!**

---

**D. Erreur de Sync (Suspect ⚠️)**
```sql
SELECT
  order_id,
  order_value,
  order_subtotal,
  items_count,
  order_created_at
FROM shopify_unified
WHERE order_value = 0
  AND order_subtotal > 0  -- Subtotal existe mais order_value = 0
  AND order_tags NOT LIKE '%test%';
```

**Explication:** Erreur de synchronisation Airbyte ou bug Shopify. **À investiguer!**

---

### Cas 2: Revenue à $0 (Marketing Table)

#### Possibilités:

**A. Journée Sans Vente (Rare mais possible)**
```sql
SELECT
  date,
  channel,
  ad_spend,
  revenue,
  ad_clicks
FROM marketing_unified
WHERE revenue = 0
  AND ad_spend > 0;
```

**Explication:** Ads ont tourné mais aucune vente ce jour-là.
- Si **1-2 jours:** Peut-être normal (conversion lag)
- Si **>3 jours:** Problème! (Tracking cassé, campaign sous-performant)

---

**B. Attribution Manquante (Suspect ⚠️)**
```sql
-- Comparer avec Shopify direct
WITH shopify_sales AS (
  SELECT
    order_date AS date,
    SUM(order_value) AS total_shopify_revenue
  FROM shopify_unified
  WHERE order_date >= CURRENT_DATE() - 7
  GROUP BY order_date
),

marketing_sales AS (
  SELECT
    date,
    SUM(revenue) AS total_marketing_revenue
  FROM marketing_unified
  WHERE date >= CURRENT_DATE() - 7
  GROUP BY date
)

SELECT
  s.date,
  s.total_shopify_revenue,
  m.total_marketing_revenue,
  s.total_shopify_revenue - COALESCE(m.total_marketing_revenue, 0) AS unattributed_revenue
FROM shopify_sales s
LEFT JOIN marketing_sales m
  ON s.date = m.date
WHERE s.total_shopify_revenue > 0
  AND (m.total_marketing_revenue IS NULL OR m.total_marketing_revenue = 0);
```

**Explication:** Ventes Shopify existent mais pas dans marketing_unified.
**Cause:** Attribution manquante (pas de UTM, direct traffic non comptabilisé)

---

**C. Période Hors Campagne (Normal ✅)**
```sql
SELECT
  date,
  channel,
  ad_spend,
  revenue
FROM marketing_unified
WHERE revenue = 0
  AND ad_spend = 0;
```

**Explication:** Aucune campagne ce jour-là. **Normal!**

---

### Cas 3: Impressions/Clicks à 0 (Ads Data)

#### Possibilités:

**A. Campaign Paused (Normal ✅)**
```sql
SELECT
  date,
  ga_campaign_name,
  ga_campaign_status,
  ga_impressions,
  ga_clicks
FROM google_ads_unified
WHERE ga_impressions = 0
  AND ga_campaign_status = 'PAUSED';
```

**Explication:** Campagne en pause. **Normal!**

---

**B. Budget Épuisé (Normal ✅)**
```sql
SELECT
  date,
  fb_campaign_name,
  fb_impressions,
  fb_spend,
  LAG(fb_spend) OVER (PARTITION BY fb_campaign_name ORDER BY date) AS prev_day_spend
FROM facebook_unified
WHERE fb_impressions = 0
  AND prev_day_spend > 0;  -- Était actif hier
```

**Explication:** Budget quotidien atteint tôt dans la journée. **Normal!**

---

**C. Sync Pas Encore Fait (Temporaire ⚠️)**
```sql
SELECT
  date,
  channel,
  ad_impressions,
  ad_spend
FROM marketing_unified
WHERE date >= CURRENT_DATE() - 1
  AND ad_impressions = 0;
```

**Explication:** Airbyte n'a pas encore synchronisé les données d'hier/aujourd'hui.
**Action:** Attendre le prochain sync (vérifier avec freshness check)

---

## 📊 Vue avec Explications Automatiques

Créons une vue qui ajoute des explications pour les 0:

```sql
CREATE OR REPLACE VIEW `hulken.ads_data.marketing_unified_with_explanations` AS

SELECT
  *,

  -- Explanation for revenue = 0
  CASE
    WHEN revenue = 0 AND ad_spend = 0 THEN 'No campaign running'
    WHEN revenue = 0 AND ad_spend > 0 AND ad_clicks < 10 THEN 'Low traffic - not enough clicks'
    WHEN revenue = 0 AND ad_spend > 0 AND ad_clicks >= 10 THEN 'Attribution issue or conversion lag'
    WHEN revenue = 0 THEN 'Unknown - investigate'
    ELSE 'Normal'
  END AS revenue_zero_explanation,

  -- Explanation for impressions = 0
  CASE
    WHEN ad_impressions = 0 AND ad_spend = 0 THEN 'Campaign paused or budget exhausted'
    WHEN ad_impressions = 0 AND ad_spend > 0 THEN 'Data sync issue - check Airbyte'
    ELSE 'Normal'
  END AS impressions_zero_explanation,

  -- Flag suspicious zeros
  CASE
    WHEN (revenue = 0 AND ad_spend > 100 AND ad_clicks > 50)
      OR (ad_impressions = 0 AND ad_spend > 0) THEN true
    ELSE false
  END AS is_suspicious_zero

FROM `hulken.ads_data.marketing_unified`;
```

**Usage:**
```sql
-- Trouver tous les 0 suspects
SELECT
  date,
  channel,
  revenue,
  ad_spend,
  ad_clicks,
  revenue_zero_explanation,
  impressions_zero_explanation
FROM marketing_unified_with_explanations
WHERE is_suspicious_zero = true
ORDER BY date DESC;
```

---

## 🎯 Checklist: Interpréter les Données

Quand tu vois un chiffre dans le rapport, demande-toi:

### 1. **Période**
- [ ] Quelle est la période actuelle? (Mois en cours? Dernier mois complet?)
- [ ] Période de comparaison claire? (vs même mois l'an dernier? vs mois précédent?)
- [ ] Label visible dans le rapport?

### 2. **Source**
- [ ] D'où viennent les données? (BigQuery? Shopify direct? API?)
- [ ] Dernière sync date visible?
- [ ] Data freshness OK (<48h)?

### 3. **Calcul**
- [ ] Comment le KPI est calculé? (SUM? AVG? SAFE_DIVIDE?)
- [ ] Filtres appliqués? (Date range? Channel? Campaign status?)
- [ ] Exclusions? (Test orders? Cancelled orders?)

### 4. **Contexte**
- [ ] Valeur normale pour cette métrique?
- [ ] Tendance cohérente avec historique?
- [ ] Anomalies expliquées?

---

## 🔧 Fix: Ajouter Périodes Partout

### Dans les Vues BigQuery

**Mettre à jour executive_summary_monthly:**
```sql
CREATE OR REPLACE VIEW `hulken.ads_data.executive_summary_monthly` AS

SELECT
  month,

  -- PERIOD LABELS (NEW!)
  FORMAT_DATE('%B %Y', month) AS period_label,
  FORMAT_DATE('%B %Y', DATE_SUB(month, INTERVAL 1 YEAR)) AS comparison_period_label,
  'YoY' AS comparison_type,

  -- Metrics (reste pareil)
  gross_revenue,
  net_revenue,
  ...
  gross_revenue_yoy,
  net_revenue_yoy
FROM (...);
```

### Dans Looker Studio

**Template de Scorecard amélioré:**

1. **Metric:** `SUM(revenue)`
2. **Comparison type:** `Previous year`
3. **Comparison label:** `vs Feb 2025`
4. **Scorecard name:** `Revenue - Feb 2026`

### Dans PowerPoint

**Chaque slide doit avoir en header:**
```
[Section Name] - [Current Period]
Comparison: [Comparison Period] ([Comparison Type])
Data as of: [Last Sync Date]
```

Exemple:
```
Executive Summary - February 2026
Comparison: February 2025 (Year-over-Year)
Data as of: February 14, 2026
```

---

## ✅ Résumé

### Pourcentages Sans Contexte → FIX

1. **Toujours inclure:**
   - Période actuelle (ex: "February 2026")
   - Période de comparaison (ex: "vs February 2025")
   - Type de comparaison (ex: "YoY", "MoM")

2. **Dans tous les rapports:**
   - BigQuery: Labels de période dans les requêtes
   - Looker: Comparison labels + Date range picker
   - PowerPoint: Headers avec périodes + Footer avec dates

### Valeurs à 0 → COMPRENDRE

| Type de 0 | Cas Normal ✅ | Cas Suspect ⚠️ |
|-----------|--------------|---------------|
| **Order value = 0** | Test order, 100% discount, échantillon gratuit | Subtotal > 0 mais order_value = 0 |
| **Revenue = 0** | No campaign, budget épuisé, 1-2 jours sans vente | >3 jours sans vente avec ad spend |
| **Impressions = 0** | Campaign paused, hors période | Impressions = 0 mais ad_spend > 0 |

### Action

1. **Créer la vue avec explications:**
   ```bash
   # Copier la requête SQL ci-dessus dans BigQuery Console et exécuter
   ```

2. **Utiliser dans dashboard Looker:**
   - Source: `marketing_unified_with_explanations`
   - Filtre: `is_suspicious_zero = true`
   - Alert visuel quand des 0 suspects détectés

3. **Inclure dans workflow:**
   - Étape 7 du master_workflow.py vérifie déjà les anomalies
   - Logs sauvegardés dans `logs/anomalies_*.txt`

🎉 **Plus de confusion!**

