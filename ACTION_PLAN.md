# PLAN D'ACTION - Réponses à toutes vos questions

**Date:** 2026-02-13
**Projet:** Hulken / Better Signal

---

## ✅ Ce qui a été créé aujourd'hui

### 1. Documentation complète

#### [docs/MASTER_QUESTIONS_ANSWERS.md](docs/MASTER_QUESTIONS_ANSWERS.md)
Document maître répondant à **TOUTES** vos questions:
- Comment rendre vscode_config portable
- Comment modifier GitHub
- Comment renommer tables/colonnes
- Pourquoi shopify_live_inventory_items est vide
- Pourquoi live_reconciliation n'a pas détecté la table vide
- Comment détecter automatiquement les nouvelles tables Airbyte
- Comment fusionner toutes les tables sources (Shopify, Facebook, TikTok)
- Pourquoi total_spent = 0 dans shopify_live_customers
- Pourquoi order_name a deux formats différents
- Où trouver le Conversion Rate Facebook
- Comment harmoniser les colonnes (index/feature/target)
- Que faire quand il y a des différences
- Et TOUTES vos autres questions!

**👉 LIRE CE DOCUMENT EN PRIORITÉ**

---

### 2. Scripts automatiques créés

#### [data_validation/table_monitoring.py](data_validation/table_monitoring.py)
**Script de monitoring automatique** qui détecte:
- ✅ Tables vides (comme shopify_live_inventory_items)
- ✅ Nouvelles tables ajoutées par Airbyte
- ✅ Tables non synchronisées depuis 48h+
- ✅ Tables manquantes (attendues mais absentes)

**Usage:**
```bash
# Première fois: créer la baseline
python data_validation/table_monitoring.py --create-baseline

# Ensuite: vérifier régulièrement
python data_validation/table_monitoring.py --check

# Sauvegarder le rapport
python data_validation/table_monitoring.py --check --output report.txt
```

**⏰ À planifier:** Exécuter quotidiennement (via cron ou Task Scheduler)

---

#### [sql/create_unified_tables.sql](sql/create_unified_tables.sql)
**Script SQL complet** pour créer les tables unifiées selon vos specifications:

**Tables créées:**
1. **shopify_unified** - Toutes les tables Shopify fusionnées
   - shopify_live_orders_clean (base)
   - shopify_live_customers_clean (via email_hash)
   - shopify_live_items (via order_id)
   - shopify_live_transactions (via order_id)
   - shopify_utm (via order_id)
   - shopify_live_order_refunds (via order_id)

2. **facebook_unified** - Facebook Ads avec métriques calculées
   - CTR, CPC, CPM automatiquement calculés

3. **tiktok_unified** - TikTok Ads avec métriques calculées
   - CTR, CPC, CPM, Conversion Rate, CPA calculés

4. **marketing_unified** - MASTER TABLE combinant TOUTES les sources
   - Shopify + Facebook + TikTok
   - ROAS, CPA, AOV automatiquement calculés

**Exécution:**
```bash
# Copier-coller dans BigQuery Console
# Ou exécuter via bq CLI:
bq query --use_legacy_sql=false < sql/create_unified_tables.sql
```

**⚠️ Important:** Prend 5-10 minutes à exécuter. Tester d'abord sur une petite période.

---

### 3. Configuration portable

#### [setup_new_project.sh](setup_new_project.sh)
Script de setup pour rendre vscode_config réutilisable sur d'autres projets.

**Usage:**
```bash
./setup_new_project.sh
```

**Ce qu'il fait:**
1. Collecte les infos du nouveau projet
2. Crée le fichier .env avec vos credentials
3. Installe les dépendances Python
4. Teste la connexion BigQuery
5. Initialise Git (optionnel)
6. Crée la baseline de monitoring

#### [data_validation/.env.template](data_validation/.env.template)
Template de configuration pour vos credentials.

---

### 4. Structure nettoyée

**Avant:**
```
vscode_config/
├── 25 fichiers mélangés
└── 8 dossiers
```

**Après:**
```
vscode_config/
├── README.md                    # 📖 Guide complet
├── ACTION_PLAN.md               # 📋 Ce document
├── setup_new_project.sh         # 🔧 Setup portable
│
├── sql/                         # Scripts SQL organisés
│   ├── README.md
│   ├── create_unified_tables.sql ⭐ NOUVEAU
│   ├── scheduled_refresh_clean_tables.sql
│   └── ...
│
├── data_validation/
│   ├── live_reconciliation.py
│   ├── table_monitoring.py       ⭐ NOUVEAU
│   └── .env.template             ⭐ NOUVEAU
│
├── docs/
│   └── MASTER_QUESTIONS_ANSWERS.md ⭐ NOUVEAU
│
├── archive/                     # Fichiers obsolètes
└── ...
```

---

## 🎯 ACTIONS IMMÉDIATES À FAIRE

### Priorité 1: Comprendre vos données

1. **Lire le document maître**
   ```bash
   open notebooks/vscode_config/docs/MASTER_QUESTIONS_ANSWERS.md
   ```

2. **Créer la baseline de monitoring**
   ```bash
   cd /Users/raphael_sebbah/Documents/Projects/Hulken/notebooks/vscode_config
   python data_validation/table_monitoring.py --create-baseline
   ```

3. **Vérifier l'état actuel des tables**
   ```bash
   python data_validation/table_monitoring.py --check
   ```
   Cela vous dira exactement:
   - Quelles tables sont vides (comme shopify_live_inventory_items)
   - Quelles tables sont nouvelles
   - Quelles tables ne sont pas synchronisées

---

### Priorité 2: Créer les tables unifiées

**Exécuter le script SQL dans BigQuery:**

```bash
# Option 1: Via BigQuery Console
# 1. Ouvrir https://console.cloud.google.com/bigquery?project=hulken
# 2. Copier-coller le contenu de sql/create_unified_tables.sql
# 3. Exécuter (Ctrl+Enter)

# Option 2: Via bq CLI
bq query --use_legacy_sql=false < sql/create_unified_tables.sql
```

**Résultat:** Vous aurez 4 nouvelles tables:
- `hulken.ads_data.shopify_unified`
- `hulken.ads_data.facebook_unified`
- `hulken.ads_data.tiktok_unified`
- `hulken.ads_data.marketing_unified` ⭐ MASTER TABLE

---

### Priorité 3: Diagnostiquer les problèmes identifiés

#### Pourquoi shopify_live_inventory_items est vide?

**Vérifier dans Shopify API:**
```bash
curl -H "X-Shopify-Access-Token: YOUR_TOKEN" \
  https://hulken-inc.myshopify.com/admin/api/2024-01/inventory_items.json
```

**Vérifier dans Airbyte:**
1. Ouvrir http://34.22.139.11:8000
2. Connection Shopify → BigQuery
3. Vérifier si "inventory_items" est coché dans le sync
4. Vérifier les logs de sync

**Vérifier les permissions:**
- Scope API `read_inventory` requis
- Vérifier dans Shopify Admin > Apps > Private App

---

#### Pourquoi total_spent = 0 pour beaucoup de clients?

**Requête de diagnostic:**
```sql
-- Combien de clients avec total_spent = 0?
SELECT
  COUNT(*) AS customers_with_zero,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM `hulken.ads_data.shopify_live_customers_clean`) AS percentage
FROM `hulken.ads_data.shopify_live_customers_clean`
WHERE CAST(total_spent AS FLOAT64) = 0;

-- Ont-ils vraiment des commandes?
SELECT
  c.id AS customer_id,
  c.total_spent AS shopify_total_spent,
  COUNT(o.id) AS actual_order_count,
  SUM(CAST(o.total_price AS FLOAT64)) AS calculated_total_spent
FROM `hulken.ads_data.shopify_live_customers_clean` c
LEFT JOIN `hulken.ads_data.shopify_live_orders_clean` o
  ON c.email_hash = o.email_hash
WHERE CAST(c.total_spent AS FLOAT64) = 0
GROUP BY c.id, c.total_spent
HAVING COUNT(o.id) > 0
LIMIT 100;
```

**Si le problème persiste:**
- Utiliser la table `shopify_unified` qui recalcule total_spent depuis les orders

---

#### Pourquoi order_name a deux formats (#595395 vs X-566085-1)?

**Explication:**
- **#XXXXXX** = Commandes Shopify normales
- **X-XXXXXX-X** = Commandes de marketplace (Amazon, eBay, etc.)

**Vérification:**
```sql
SELECT
  CASE
    WHEN name LIKE '#%' THEN 'Shopify Standard'
    WHEN name LIKE 'X-%' THEN 'Marketplace/External'
    ELSE 'Other'
  END AS order_type,
  source_name,
  COUNT(*) AS count
FROM `hulken.ads_data.shopify_live_orders_clean`
GROUP BY order_type, source_name
ORDER BY count DESC;
```

**Solution:** Utiliser `shopify_unified.order_number_clean` qui extrait juste le numéro.

---

#### Où trouver le Conversion Rate dans Facebook?

**Réponse:** Pas de colonne directe. Il faut calculer.

**Dans facebook_unified:**
```sql
SELECT
  fb_campaign_name,
  date,
  fb_clicks,
  -- Extraire conversions du JSON actions
  CAST(JSON_EXTRACT_SCALAR(fb_actions_json, '$[0].value') AS INT64) AS conversions,
  -- Calculer conversion rate
  SAFE_DIVIDE(
    CAST(JSON_EXTRACT_SCALAR(fb_actions_json, '$[0].value') AS INT64),
    fb_clicks
  ) * 100 AS conversion_rate_percent
FROM `hulken.ads_data.facebook_unified`
WHERE fb_actions_json IS NOT NULL
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY date DESC;
```

---

## 📊 STRUCTURE DES DONNÉES - Résumé

### Tables par source

**Shopify:**
```
shopify_live_orders          → shopify_live_orders_clean
shopify_live_customers       → shopify_live_customers_clean
shopify_live_items           → (utilisée dans shopify_unified)
shopify_live_transactions    → (utilisée dans shopify_unified)
shopify_utm                  → (utilisée dans shopify_unified)
shopify_live_order_refunds   → (utilisée dans shopify_unified)

                             ↓
                    shopify_unified ⭐
                    (TOUTES les tables liées)
```

**Facebook:**
```
facebook_ads_insights        → facebook_insights (vue dédupliquée)
                             ↓
                    facebook_unified ⭐
                    (avec métriques calculées)
```

**TikTok:**
```
tiktokads_reports_daily      → tiktok_ads_reports_daily (vue dédupliquée)
                             ↓
                    tiktok_unified ⭐
                    (avec métriques calculées)
```

**Master Table:**
```
shopify_unified + facebook_unified + tiktok_unified
                             ↓
                    marketing_unified ⭐⭐⭐
                    (TOUTES les sources + ROAS, CPA, etc.)
```

---

## 🔄 WORKFLOW RECOMMANDÉ

### Quotidien

1. **Vérifier la santé des tables**
   ```bash
   python data_validation/table_monitoring.py --check
   ```

2. **Valider l'intégrité des données**
   ```bash
   python data_validation/live_reconciliation.py --platform all
   ```

---

### Hebdomadaire

1. **Vérifier les nouvelles tables Airbyte**
   ```bash
   python data_validation/table_monitoring.py --check --output weekly_report.txt
   ```

2. **Analyser les performances dans marketing_unified**
   ```sql
   SELECT
     date,
     channel,
     SUM(revenue) AS revenue,
     SUM(ad_spend) AS spend,
     SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas
   FROM `hulken.ads_data.marketing_unified`
   WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
   GROUP BY date, channel
   ORDER BY date DESC, revenue DESC;
   ```

---

### Mensuel

1. **Recalculer les tables unifiées**
   ```bash
   # Ré-exécuter le script SQL
   bq query --use_legacy_sql=false < sql/create_unified_tables.sql
   ```

2. **Nettoyer les anciennes données** (optionnel)
   ```sql
   -- Supprimer les données > 2 ans (si besoin d'économiser)
   DELETE FROM `hulken.ads_data.facebook_insights`
   WHERE date_start < DATE_SUB(CURRENT_DATE(), INTERVAL 730 DAY);
   ```

---

## 🚀 PROCHAINES ÉTAPES (Optionnel)

### Améliorations futures

1. **Dashboard Looker Studio**
   - Connecter `marketing_unified` à Looker Studio
   - Créer des dashboards automatiques

2. **Alertes automatiques**
   - Configurer des alertes email quand:
     - Une table devient vide
     - Une nouvelle table est ajoutée
     - live_reconciliation détecte une divergence > 5%

3. **Machine Learning**
   - Prédiction du LTV client
   - Optimisation du budget publicitaire
   - Détection d'anomalies

4. **Restructuration complète** (si souhaité)
   - Migrer vers la structure `raw/clean/unified/mart`
   - Détaillée dans MASTER_QUESTIONS_ANSWERS.md

---

## 📞 SUPPORT

**Documentation:**
- [README.md](README.md) - Guide général
- [docs/MASTER_QUESTIONS_ANSWERS.md](docs/MASTER_QUESTIONS_ANSWERS.md) - Toutes les questions
- [sql/README.md](sql/README.md) - Documentation SQL

**Scripts:**
- [data_validation/table_monitoring.py](data_validation/table_monitoring.py) - Monitoring
- [data_validation/live_reconciliation.py](data_validation/live_reconciliation.py) - Validation
- [data_explorer.py](data_explorer.py) - Exploration visuelle

**GitHub:**
- https://github.com/devops131326/Hulken_better_signal

---

## ✅ CHECKLIST FINALE

Avant de commencer, assurez-vous de:

- [ ] Lire [docs/MASTER_QUESTIONS_ANSWERS.md](docs/MASTER_QUESTIONS_ANSWERS.md)
- [ ] Créer la baseline de monitoring
- [ ] Exécuter table_monitoring.py --check
- [ ] Créer les tables unifiées (create_unified_tables.sql)
- [ ] Vérifier marketing_unified
- [ ] Planifier l'exécution quotidienne de table_monitoring.py
- [ ] Ajouter les credentials manquants dans .env
- [ ] Tester live_reconciliation.py

---

**🎉 Vous avez maintenant tous les outils pour gérer vos données Hulken de manière professionnelle!**

