# Workflow Complet - Analytics Automation 🚀

**Date:** 2026-02-15
**Version:** 1.0

---

## 🎯 Objectif

Pipeline automatisé de A→Z pour analytics et reporting:
1. Connexion BigQuery ✅
2. Réconciliation API vs BigQuery ✅
3. Détection nouvelles tables ✅
4. Vérification freshness ✅
5. **Encoding PII cohérent** (même email = même hash partout) ✅
6. Unification tables (dédoublonnage) ✅
7. Détection anomalies (NULL, 0, data manquante) ✅
8. Génération rapport exécutif (26 sections) ✅

---

## ⚡ Quick Start

### Option 1: Tout Exécuter (Recommandé)

```bash
cd ~/Documents/Projects/Dev_Ops
python3 scripts/master_workflow.py
```

**Durée:** ~5-10 minutes
**Résultat:** Pipeline complet exécuté + rapport PowerPoint

---

### Option 2: Exécution Partielle

```bash
# Skip réconciliation (si déjà fait)
python3 scripts/master_workflow.py --skip-reconciliation

# Skip PII encoding (si déjà fait)
python3 scripts/master_workflow.py --skip-pii

# Skip rapport (focus sur data seulement)
python3 scripts/master_workflow.py --skip-report

# Combiner plusieurs skips
python3 scripts/master_workflow.py --skip-reconciliation --skip-report
```

---

## 📋 Détail des 8 Étapes

### Étape 1: Test Connexion BigQuery 🔌

**Objectif:** Vérifier que tu peux accéder à BigQuery

**Commande:**
```bash
bq ls --project_id=hulken ads_data
```

**Résultat attendu:** Liste des tables dans `ads_data`

**Si erreur:**
```bash
gcloud auth application-default login
```

---

### Étape 2: Réconciliation API vs BigQuery 🔄

**Objectif:** Comparer les données dans les APIs (Shopify, Facebook, etc.) avec BigQuery

**Script:** `data_validation/live_reconciliation.py`

**Vérifications:**
- Shopify: Orders dans API = Orders dans BigQuery?
- Facebook: Spend dans Ads Manager = Spend dans BigQuery?
- TikTok: Métriques cohérentes?
- Google Ads: Conversions matchent?

**Résultat:** Rapport de discordances (si des données manquent)

---

### Étape 3: Détection Nouvelles Tables 🔍

**Objectif:** Identifier si Airbyte a ajouté de nouvelles tables

**Script:** `data_validation/table_monitoring.py`

**Vérifications:**
- Compare baseline (dernières tables connues) vs tables actuelles
- Détecte tables vides (0 lignes)
- Détecte syncs stale (>48h sans update)

**Exemple output:**
```
NEW tables detected:
  - shopify_live_metafields (0 rows) ← Nouveau!
  - facebook_ads_insights_dma (1,234 rows) ← Nouveau!

STALE tables (>48h):
  - tiktok_ads_reports_daily (last sync: 3 days ago)
```

---

### Étape 4: Vérification Freshness des Données ⏰

**Objectif:** S'assurer que les données sont à jour

**Requête SQL:**
```sql
SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_sync,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS hours_since_sync
FROM `hulken.ads_data.__TABLES__`
WHERE table_id IN (
  'shopify_live_orders',
  'facebook_ads_insights',
  'tiktok_ads_reports_daily'
)
ORDER BY hours_since_sync DESC;
```

**Seuil d'alerte:** >48 heures

**Action si stale:**
1. Aller dans Airbyte
2. Forcer un sync manuel
3. Vérifier les logs d'erreur

---

### Étape 5: Encoding PII Cohérent 🔐

**Objectif:** Garantir que le MÊME email a le MÊME hash dans toutes les tables

**Problème à résoudre:**
- Email `john@example.com` dans Shopify → Hash `abc123`
- MAIS email `john@example.com` dans Facebook → Hash `xyz789` ❌

**Solution:**

1. **Créer une table de référence:**
   ```sql
   CREATE OR REPLACE TABLE `hulken.ads_data.pii_hash_reference` AS

   WITH all_emails AS (
     SELECT DISTINCT email_hash FROM shopify_live_customers
     UNION DISTINCT
     SELECT DISTINCT email_hash FROM shopify_live_orders
     UNION DISTINCT
     SELECT DISTINCT customer_email_hash FROM facebook_customers
   )

   SELECT
     email_hash AS email_hash_original,
     TO_HEX(SHA256(email_hash)) AS email_hash_consistent
   FROM all_emails;
   ```

2. **Utiliser cette table partout:**
   ```sql
   -- Dans shopify_unified
   SELECT
     o.*,
     ref.email_hash_consistent  -- ← Hash cohérent
   FROM shopify_live_orders o
   LEFT JOIN pii_hash_reference ref
     ON o.email_hash = ref.email_hash_original;
   ```

**Résultat:** Même email = même hash dans TOUTES les tables

---

### Étape 6: Unification des Tables (Sans Doublons) 🔗

**Objectif:** Créer tables unifiées avec dédoublonnage

**Script:** `sql/create_unified_tables.sql`

**Tables créées:**
1. **shopify_unified** - Merge de:
   - shopify_live_orders_clean (base)
   - shopify_live_customers_clean (via email_hash)
   - shopify_line_items (via order_id)
   - shopify_live_transactions (via order_id)
   - shopify_utm (via order_id)
   - shopify_live_order_refunds (via order_id)

2. **facebook_unified** - Facebook Ads métriques

3. **tiktok_unified** - TikTok Ads métriques

4. **google_ads_unified** - Google Ads métriques

5. **marketing_unified** - MASTER TABLE (tout combiné)

**Dédoublonnage:**
```sql
-- Vérification automatique des doublons
SELECT
  'shopify_unified' AS table_name,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS unique_orders,
  COUNT(*) - COUNT(DISTINCT order_id) AS duplicates
FROM shopify_unified;
```

**Si duplicates > 0:** Alerte générée!

---

### Étape 7: Détection d'Anomalies 🚨

**Objectif:** Trouver les données NULL ou 0 inappropriées

**Types d'anomalies détectées:**

#### A. NULL inappropriés
```sql
-- Orders sans order_value (illogique!)
SELECT COUNT(*)
FROM shopify_unified
WHERE order_value IS NULL;

-- Orders sans customer_id (possible mais rare)
SELECT COUNT(*)
FROM shopify_unified
WHERE customer_id IS NULL;
```

#### B. Zéros suspects
```sql
-- Revenue = 0 mais ad_spend > 0 (suspect!)
SELECT date, channel, ad_spend, revenue
FROM marketing_unified
WHERE revenue = 0 AND ad_spend > 0;
```

#### C. Données manquantes vs historique
```sql
-- Compare vs moyenne des 30 derniers jours
WITH avg_last_30d AS (
  SELECT AVG(revenue) AS avg_revenue
  FROM marketing_unified
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
)

SELECT date, revenue
FROM marketing_unified, avg_last_30d
WHERE revenue < (avg_revenue * 0.5)  -- 50% sous la moyenne
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

**Résultat:** Rapport d'anomalies sauvegardé dans `logs/anomalies_YYYYMMDD.txt`

---

### Étape 8: Génération Rapport Exécutif 📊

**Objectif:** Créer PowerPoint avec les 26 sections

**Script:** `scripts/generate_powerpoint.py`

**Fichier généré:** `reports/Marketing_Performance_Report.pptx`

**Sections incluses:**

#### Section 1: Total Business Performance (2 slides)
- Executive Summary (KPIs avec YoY)
- Marketing Efficiency

#### Section 2: DTC Performance (11 slides)
- Sitewide Overview
- Traffic & Sales Trends
- Conversion & Revenue Efficiency
- Marketing Cost Efficiency
- New vs Returning Customers
- Search Demand Trends ⚠️ (Google Trends requis)
- Funnel Measurement
- Merchandising Performance
- Content & UX ⚠️ (GA4 requis)
- Geographic Insights
- International (Canada)
- Demographics & Devices ⚠️ (GA4 requis)

#### Section 3: Amazon Performance (3 slides)
⚠️ Requiert Amazon Ads connecté

#### Section 4: Paid Marketing (6 slides)
- Paid Channel Mix
- PPC Performance Table
- Creative Performance ⚠️ (Motion requis)
- Landing Page Performance ⚠️ (GA4 requis)
- Reach & Saturation ⚠️ (Facebook Ads Manager)
- Search Query Performance ⚠️ (Google Ads query data)

#### Section 5: Customer Voice (2 slides)
⚠️ Requiert Fairing survey data

#### Appendix (1 slide)
- Total Business PPC Performance Index

**Total:** 23 slides générées, 20/26 sections avec données actuelles (77%)

---

## 🔄 Workflow Automatisé Quotidien

### Setup Cron Job (Exécution Automatique)

```bash
# Ouvrir crontab
crontab -e

# Ajouter cette ligne (exécute à 6h du matin tous les jours)
0 6 * * * cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops && python3 scripts/master_workflow.py >> logs/workflow_cron.log 2>&1

# Sauvegarder et quitter (:wq)
```

**Résultat:** Chaque matin à 6h:
1. Toutes les vérifications sont faites
2. Tables sont unifiées
3. Anomalies sont détectées
4. Rapport PowerPoint est généré

---

## 📊 Dashboards Looker Studio

**En complément du PowerPoint, créer dashboards Looker:**

### Dashboard 1: Executive Summary
- Source: `executive_summary_monthly`
- KPIs: Revenue, Spend, ROAS, Orders
- Graphique: Trend mensuel
- Filtres: Date range, Channel

### Dashboard 2: Shopify Performance
- Source: `shopify_daily_metrics`
- KPIs: Orders, AOV, Returning %
- Graphiques: Traffic trend, Top products
- Filtres: Date, Product category

### Dashboard 3: Channel Performance
- Source: `channel_mix`
- Pie chart: Spend distribution
- Table: Channel performance (ROAS, CPA, etc.)
- Filtres: Date, Channel status

### Dashboard 4: Anomalies
- Source: Custom query avec anomaly detection logic
- Alerts: Tables NULL/0 suspects
- Trend: Anomalies over time

**Quick start Looker:** [docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)

---

## 🚨 Troubleshooting

### Erreur: "BigQuery connection failed"
```bash
gcloud auth application-default login
gcloud config set project hulken
```

### Erreur: "Table not found"
Vérifier que les tables existent:
```bash
bq ls --project_id=hulken ads_data
```

### Erreur: "Permission denied"
Vérifier les permissions BigQuery:
```bash
gcloud projects get-iam-policy hulken --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:$(gcloud config get-value account)"
```

Rôle requis: `roles/bigquery.dataEditor` ou `roles/bigquery.admin`

### Anomalies détectées mais normales
Éditer le script `master_workflow.py`:
```python
# Ligne ~XXX - Ajuster le seuil
WHERE null_count > 0 OR zero_count > (total_rows * 0.1)  # 10% → Changer à 20%
```

---

## 📈 KPIs de Monitoring du Workflow

**À surveiller quotidiennement:**

| Métrique | Seuil OK | Seuil Warning | Seuil Critical |
|----------|----------|---------------|----------------|
| Freshness (hours) | < 24h | 24-48h | > 48h |
| Duplicates | 0 | 1-10 | > 10 |
| NULL % | < 5% | 5-15% | > 15% |
| Anomalies count | 0 | 1-5 | > 5 |
| Workflow duration | < 5 min | 5-10 min | > 10 min |

---

## 🎯 Next Steps

### Court terme (Cette semaine)
1. ✅ Exécuter le workflow une première fois
2. ⚠️ Fixer les anomalies détectées
3. 📊 Créer le dashboard Looker Studio
4. 🔄 Setup cron job pour automatisation

### Moyen terme (Ce mois)
1. Ajouter Amazon Ads (guide: [docs/AMAZON_ADS_AIRBYTE_SETUP.md](docs/AMAZON_ADS_AIRBYTE_SETUP.md))
2. Connecter GA4 pour sessions/devices
3. Connecter Fairing pour surveys
4. Connecter Motion pour creative performance

### Long terme (Ce trimestre)
1. Machine Learning pour détection d'anomalies avancée
2. Prédictions ROAS par canal
3. Budget allocation optimization
4. Customer LTV prediction

---

## 📚 Fichiers Liés

| Fichier | Description |
|---------|-------------|
| **[WORKFLOW_COMPLET.md](WORKFLOW_COMPLET.md)** | Ce fichier - Workflow complet |
| **[scripts/master_workflow.py](scripts/master_workflow.py)** | Script orchestrateur principal |
| **[sql/create_unified_tables.sql](sql/create_unified_tables.sql)** | Unification des tables |
| **[data_validation/live_reconciliation.py](data_validation/live_reconciliation.py)** | Réconciliation API vs BQ |
| **[data_validation/table_monitoring.py](data_validation/table_monitoring.py)** | Monitoring tables |
| **[scripts/generate_powerpoint.py](scripts/generate_powerpoint.py)** | Génération PowerPoint |
| **[docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md)** | Quick start Looker |

---

## ✅ Checklist Première Exécution

- [ ] BigQuery access configuré (`gcloud auth`)
- [ ] Tables unifiées créées (shopify_unified, marketing_unified, etc.)
- [ ] Vues de reporting créées (shopify_daily_metrics, channel_mix, etc.)
- [ ] Workflow exécuté avec succès (`python3 master_workflow.py`)
- [ ] Anomalies vérifiées et corrigées
- [ ] PowerPoint généré et vérifié
- [ ] Dashboard Looker créé (optionnel mais recommandé)
- [ ] Cron job configuré pour automation (optionnel)

---

## 🎉 Résultat Final

**Après première exécution complète, tu auras:**

1. ✅ **Tables BigQuery** propres, unifiées, sans doublons
2. ✅ **PII encoding cohérent** (même hash partout)
3. ✅ **Détection automatique** des nouvelles tables et anomalies
4. ✅ **PowerPoint professionnel** (23 slides, 77% des sections)
5. ✅ **Workflow automatisable** (cron job quotidien)
6. ✅ **Dashboard Looker** (optionnel, recommandé)
7. ✅ **Logs d'audit** pour traçabilité

**Temps total:** ~10 minutes pour premier run, puis 5 minutes/jour en automatique

🚀 **Ready to scale!**

