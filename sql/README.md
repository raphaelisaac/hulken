# Scripts SQL BigQuery

Ce dossier contient tous les scripts SQL pour BigQuery utilisés dans le projet Hulken.

---

## Scripts disponibles

### 1. **scheduled_refresh_clean_tables.sql**
**Usage:** Planifié quotidiennement dans BigQuery
**Fréquence:** Tous les jours à 10:00 UTC
**Description:** Rafraîchit les tables Shopify "clean" en effectuant:
- Déduplication (garde la dernière extraction Airbyte)
- Hashage PII (emails, téléphones, adresses)
- Préservation des hash existants quand les données brutes sont nullifiées

**Tables affectées:**
- `hulken.ads_data.shopify_live_orders_clean`
- `hulken.ads_data.shopify_live_customers_clean`

**Pourquoi c'est important:**
- Garantit des données sans doublons pour l'analyse
- Protège les données personnelles (RGPD)
- Maintient l'intégrité des hash même après nullification PII

---

### 2. **EXPORT_TIKTOK_DATA.sql**
**Usage:** Manuel (export ad-hoc)
**Description:** Exporte toutes les données TikTok Ads pour analyse externe ou backup.

**Métriques exportées:**
- Dépenses (spend)
- Impressions
- Clics
- Conversions
- Dates de campagnes

**Utilisation:**
```sql
-- Copier-coller dans BigQuery Console
-- Ajuster les dates si nécessaire
-- Exporter les résultats en CSV
```

---

### 3. **create_facebook_dedup_views.sql**
**Usage:** Configuration initiale
**Description:** Crée des vues dédupliquées pour Facebook Ads Insights.

**Problème résolu:**
- Airbyte peut créer des doublons lors des syncs incrémentaux
- Les vues garantissent qu'on a une seule ligne par combinaison date/campaign/adset/ad

**Vue créée:**
- `facebook_insights` (vue dédupliquée de `facebook_ads_insights`)

---

### 4. **fix_tiktok_dedup_views.sql**
**Usage:** Maintenance / Correction
**Description:** Corrige les vues de déduplication TikTok en cas de problème.

**Quand l'utiliser:**
- Si vous constatez des doublons dans les rapports TikTok
- Après une modification de schéma Airbyte
- Si la vue `tiktok_ads_reports_daily` montre des incohérences

---

## Conventions de nommage

- **Tables brutes Airbyte:** `platform_table_name` (ex: `facebook_ads_insights`, `shopify_live_orders`)
- **Tables/vues nettoyées:** `platform_table_name_clean` ou sans préfixe (ex: `facebook_insights`, `shopify_live_orders_clean`)
- **Views de déduplication:** Même nom que la table source sans suffixe Airbyte

---

## Exécution dans BigQuery

### Via Console BigQuery
1. Aller sur [BigQuery Console](https://console.cloud.google.com/bigquery)
2. Sélectionner le projet `hulken`
3. Copier-coller le script SQL
4. Cliquer sur "Run"

### Via Python
```python
from google.cloud import bigquery

client = bigquery.Client(project='hulken')

with open('sql/scheduled_refresh_clean_tables.sql', 'r') as f:
    query = f.read()

client.query(query).result()
```

### Via bq CLI
```bash
bq query --use_legacy_sql=false < sql/scheduled_refresh_clean_tables.sql
```

---

## Planification dans BigQuery

Pour planifier un script SQL dans BigQuery:

1. Aller dans BigQuery Console
2. Cliquer sur "Scheduled queries" dans le menu
3. Cliquer sur "Create scheduled query"
4. Coller le SQL
5. Configurer:
   - **Name:** `refresh_shopify_clean_tables` (exemple)
   - **Schedule:** Daily, 10:00 UTC
   - **Destination:** (optionnel si CREATE TABLE)
6. Sauvegarder

---

## Notes importantes

- **Toujours tester sur une petite période avant d'exécuter sur toutes les données**
- **Les scripts avec CREATE OR REPLACE TABLE suppriment et recréent la table**
- **Les requêtes planifiées continuent à tourner jusqu'à ce que vous les désactiviez**
- **Vérifier les coûts BigQuery avant d'exécuter sur de gros volumes**

---

## Maintenance

**Fréquence de revue:** Trimestrielle

**Points à vérifier:**
- [ ] Les tables sources existent toujours
- [ ] Les schémas n'ont pas changé
- [ ] Les performances sont acceptables
- [ ] Les résultats correspondent aux attentes

---

*Dernière mise à jour: 2026-02-13*
