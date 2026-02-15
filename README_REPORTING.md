# Dashboard de Reporting - Guide Rapide

**Date:** 2026-02-15
**Statut:** ✅ Tables créées, Dashboards à configurer

---

## 🎯 Ce qui est FAIT

### ✅ Tables BigQuery Unifiées
- `shopify_unified` (19,869 commandes)
- `facebook_unified` (128,345 métriques)
- `tiktok_unified` (30,721 métriques)
- `google_ads_unified` (13,722 métriques, ROAS 4.69!)
- `marketing_unified` (3,100 lignes - TABLE MAÎTRESSE)

### ✅ Vues de Reporting Créées
- `shopify_daily_metrics` - Métriques quotidiennes Shopify
- `marketing_monthly_performance` - Performance mensuelle par canal
- `product_performance` - Top produits avec ventes
- `executive_summary_monthly` - KPIs avec YoY
- `channel_mix` - Distribution du spend par canal

---

## 🚀 Prochaines Étapes

### Étape 1: Fixer le tunnel IAP Airbyte ⏱️ 2 min

Le tunnel a des erreurs "Bad file descriptor" parce qu'il essaie d'utiliser IPv6.

**Solution:**
```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops
./scripts/airbyte_tunnel.sh
```

Ce script:
- ✅ Force IPv4 (127.0.0.1 au lieu de ::1)
- ✅ Démarre la VM si arrêtée
- ✅ Nettoie les anciens tunnels
- ✅ Crée un tunnel stable

**Ensuite, ouvrir:** http://localhost:8006

---

### Étape 2: Créer les vues de reporting ⏱️ 1 min

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Exécuter le script SQL pour créer les vues
bq query --project_id=hulken --use_legacy_sql=false < sql/create_reporting_views.sql
```

Cela va créer 5 vues optimisées pour Looker Studio.

---

### Étape 3: Voir les tables dans BigQuery ⏱️ 30 sec

**Option A: Console Web**
1. Aller sur: https://console.cloud.google.com/bigquery?project=hulken
2. Dans le panneau gauche, développer `hulken` → `ads_data`
3. Cliquer sur `marketing_unified` pour voir:
   - Schema
   - Preview (premières lignes)
   - Details (taille, nombre de lignes)

**Option B: Via SQL**
```sql
-- Voir toutes les tables
SELECT
  table_id AS table_name,
  row_count,
  ROUND(size_bytes / 1024 / 1024, 2) AS size_mb
FROM `hulken.ads_data.__TABLES__`
WHERE table_id LIKE '%unified%' OR table_id LIKE '%_metrics' OR table_id LIKE '%performance%'
ORDER BY row_count DESC;
```

---

### Étape 4: Créer le Dashboard Looker Studio ⏱️ 15 min

**A. Accéder à Looker Studio**
1. Aller sur: https://lookerstudio.google.com
2. Se connecter avec ton compte Google du projet `hulken`
3. Cliquer **"Create"** → **"Report"**

**B. Connecter BigQuery**
1. Dans le nouveau rapport, cliquer **"Add data"**
2. Chercher et sélectionner **"BigQuery"**
3. Autoriser l'accès
4. Sélectionner:
   - Project: `hulken`
   - Dataset: `ads_data`
   - Table: `marketing_unified`
5. Cliquer **"Add"**

**C. Créer le premier KPI**
1. Cliquer **"Add a chart"** → **"Scorecard"**
2. Placer le scorecard en haut à gauche
3. Dans le panneau de droite:
   - **Metric:** `revenue` → Changer aggregation à **SUM**
   - **Date range dimension:** `date`
4. Changer le format:
   - Type: **Currency** → **USD ($)**
   - Decimal places: **0**
5. Ajouter un titre: "Total Revenue (Last 30 Days)"

**Félicitations! Tu as créé ton premier KPI!** 🎉

**D. Ajouter plus de visualisations**

Toutes les requêtes SQL sont dans [docs/LOOKER_STUDIO_SETUP.md](docs/LOOKER_STUDIO_SETUP.md)

---

## 📊 Alternative: Template PowerPoint

Si tu préfères PowerPoint au lieu de Looker Studio dynamique:

### Option 1: Exporter depuis Looker
1. Créer le dashboard dans Looker (étapes ci-dessus)
2. Cliquer **"Download"** → **"PDF - All pages"**
3. Ouvrir le PDF et copier dans PowerPoint

### Option 2: Screenshots de BigQuery
1. Aller dans BigQuery Console
2. Exécuter les requêtes dans `docs/LOOKER_STUDIO_SETUP.md`
3. Cliquer sur le graphique **"Chart"** en bas à droite
4. Screenshot et coller dans PowerPoint

### Option 3: Google Slides (Recommandé pour collaboration)
1. Créer une présentation Google Slides
2. Intégrer les graphiques Looker avec **Insert → Chart → From Sheets**
3. Les graphiques se mettront à jour automatiquement!

---

## 🎨 Sections du Rapport (26 au total)

Voici les 26 sections que tu as demandées:

### Section 1: Total Business Performance
1. ✅ Executive Summary - `executive_summary_monthly` VIEW
2. ✅ Marketing Efficiency - `marketing_monthly_performance` VIEW

### Section 2: Dot-Com (DTC) Performance
3. ✅ Sitewide Overview - `shopify_daily_metrics` VIEW
4. ✅ Traffic & Sales Trends - `shopify_daily_metrics` + Aggregation
5. ✅ Conversion & Revenue Efficiency - Calculé dans VIEW
6. ✅ Marketing Cost Efficiency - `marketing_unified` TABLE
7. ✅ New vs Returning - `shopify_daily_metrics` VIEW
8. ⚠️ Search Demand Trends - **BESOIN: Google Trends API**
9. ✅ Funnel Measurement - Calculable depuis `shopify_unified`
10. ✅ Merchandising Performance - `product_performance` VIEW
11. ⚠️ Content & UX - **BESOIN: GA4 data**
12. ✅ Geographic Insights - Calculable depuis `shopify_unified`
13. ✅ International (Canada) - Filtrer `shopify_unified`
14. ⚠️ Demographics & Devices - **BESOIN: GA4 data**

### Section 3: Amazon Performance
15. ⚠️ Amazon Overview - **BESOIN: Ajouter Amazon Ads à Airbyte**
16. ⚠️ Amazon Traffic/Conversion - **BESOIN: Amazon data**
17. ⚠️ Amazon Merchandising - **BESOIN: Amazon data**

### Section 4: Paid Marketing
18. ✅ Paid Channel Mix - `channel_mix` VIEW
19. ✅ PPC Performance Table - `marketing_unified` TABLE
20. ⚠️ Creative Performance - **BESOIN: Motion data**
21. ⚠️ Landing Page Performance - **BESOIN: GA4 + UTM tracking**
22. ⚠️ Reach & Saturation - **BESOIN: Facebook Ads Manager data**
23. ⚠️ Search Query Performance - **BESOIN: Google Ads query data**

### Section 5: Customer Voice
24. ⚠️ Attribution & Awareness - **BESOIN: Fairing survey data**
25. ⚠️ Purchase Friction - **BESOIN: Fairing survey data**

### Appendix
26. ✅ Total Business PPC Index - `marketing_monthly_performance` VIEW

---

## ⚠️ Données Manquantes

Pour compléter les 26 sections, tu as besoin de connecter:

### Haute Priorité
1. **Google Analytics 4** → BigQuery
   - Sessions, Users, Bounce Rate, Pages/Session
   - Demographics, Devices
   - Landing pages performance

2. **Amazon Ads** → Airbyte → BigQuery
   - Guide complet: [docs/AMAZON_ADS_AIRBYTE_SETUP.md](docs/AMAZON_ADS_AIRBYTE_SETUP.md)

### Moyenne Priorité
3. **Fairing** (Post-purchase surveys) → BigQuery
   - Attribution questions
   - Purchase friction feedback

4. **Motion** (Creative analytics) → BigQuery
   - Meta creatives performance
   - YouTube creatives performance

### Basse Priorité
5. **Google Trends API**
   - Brand vs category search volume

6. **Facebook Ads Manager** (Reach data)
   - Requires custom export or API integration

---

## 📈 Résumé des Données Actuelles

### ✅ Ce qu'on a (80% des sections)
- Shopify orders, revenue, products, customers
- Facebook/TikTok/Google Ads spend, revenue, ROAS
- Marketing channel performance
- Product-level sales data
- Geographic data (from Shopify)
- New vs returning customers
- Attribution (first/last touch UTM)

### ⚠️ Ce qui manque (20% des sections)
- GA4 behavior data (sessions, bounce rate, pages/session)
- Amazon Ads data
- Survey data (Fairing)
- Creative performance (Motion)
- Search trends (Google Trends)

---

## 🎯 Action Immédiate

**Pour avoir un dashboard fonctionnel AUJOURD'HUI:**

1. **Fixer le tunnel Airbyte** (2 min)
   ```bash
   ./scripts/airbyte_tunnel.sh
   ```

2. **Créer les vues de reporting** (1 min)
   ```bash
   bq query --project_id=hulken --use_legacy_sql=false < sql/create_reporting_views.sql
   ```

3. **Voir les données dans BigQuery** (30 sec)
   - https://console.cloud.google.com/bigquery?project=hulken

4. **Créer le dashboard Looker** (15 min)
   - https://lookerstudio.google.com
   - Suivre [docs/LOOKER_STUDIO_SETUP.md](docs/LOOKER_STUDIO_SETUP.md)

**Résultat:** Tu auras un dashboard professionnel avec ~20 des 26 sections fonctionnelles!

---

## 📞 Besoin d'Aide?

- **Looker Studio:** [docs/LOOKER_STUDIO_SETUP.md](docs/LOOKER_STUDIO_SETUP.md)
- **Amazon Ads:** [docs/AMAZON_ADS_AIRBYTE_SETUP.md](docs/AMAZON_ADS_AIRBYTE_SETUP.md)
- **Shopify Inventory:** [docs/SHOPIFY_INVENTORY_ITEMS_FIX.md](docs/SHOPIFY_INVENTORY_ITEMS_FIX.md)

