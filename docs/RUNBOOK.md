# Runbook - Hulken Data Infrastructure

**Dernière mise à jour:** 2026-02-04
**Projet GCP:** hulken
**Dataset:** ads_data
**VM:** instance-20260129-133637 (us-central1-a)

---

## Quick Reference

| Service | Accès | Port |
|---------|-------|------|
| Airbyte | `localhost:8000` (via SSH tunnel) | 8000 |
| BigQuery | Console GCP ou VSCode | - |
| Looker Studio | lookerstudio.google.com | - |

```bash
# Accès rapide Airbyte (une commande)
gcloud compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap -- -L 8000:localhost:8000
# Puis ouvrir http://localhost:8000
```

---

## 1. Prérequis

### 1.1 Google Cloud SDK

```bash
# Windows (PowerShell admin)
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:TEMP\GoogleCloudSDKInstaller.exe")
& $env:TEMP\GoogleCloudSDKInstaller.exe

# Vérification
gcloud --version
```

### 1.2 Authentification GCP

```bash
gcloud auth login
gcloud config set project hulken
gcloud auth application-default login
```

### 1.3 Python (pour scripts BigQuery)

```bash
pip install google-cloud-bigquery pandas db-dtypes pyarrow python-dotenv requests
```

### 1.4 Node.js + PM2 (pour scheduling)

```bash
# Installation PM2
npm install -g pm2

# Vérification
pm2 --version
```

---

## 2. Airbyte (Data Pipelines)

### 2.1 Accès Interface

```bash
# Étape 1: SSH Tunnel
gcloud compute ssh instance-20260129-133637 \
  --zone=us-central1-a \
  --tunnel-through-iap \
  -- -L 8000:localhost:8000

# Étape 2: Ouvrir navigateur
# http://localhost:8000

# Credentials: voir .env sur la VM
```

### 2.2 Connexions Configurées

| Source | Destination | Mode | Fréquence |
|--------|-------------|------|-----------|
| Shopify (hulken-inc) | BigQuery | Full Refresh | Horaire |
| Facebook Marketing (3 comptes) | BigQuery | Incremental | Horaire |
| TikTok Marketing | BigQuery | Incremental | Horaire |

### 2.3 Tables Générées par Airbyte

**Shopify:**
- `shopify_live_orders` (8,448 rows) - Commandes récentes
- `shopify_live_customers` (10,680 rows) - Clients
- `shopify_live_products`, `shopify_live_transactions`, etc.

**Facebook:**
- `facebook_insights` (159,342 rows) - Métriques quotidiennes
- `facebook_campaigns`, `facebook_ad_sets`, `facebook_ads`

**TikTok:**
- `tiktok_ads_reports_daily` (28,723 rows) - Métriques quotidiennes
- `tiktok_campaigns`, `tiktokads`, etc.

### 2.4 Troubleshooting Airbyte

| Problème | Solution |
|----------|----------|
| Connection refused | Vérifier que le tunnel SSH est actif |
| Sync failed | Vérifier les credentials dans Sources |
| Data not appearing | Vérifier la destination BigQuery |

---

## 3. BigQuery (Data Analysis)

### 3.1 Accès Console

1. https://console.cloud.google.com/bigquery
2. Projet: `hulken`
3. Dataset: `ads_data`

### 3.2 Setup VSCode

**Extensions requises:**
- Google Cloud Code
- SQLTools + BigQuery Driver

**Test connexion:**
```python
from google.cloud import bigquery
client = bigquery.Client(project='hulken')
query = "SELECT COUNT(*) FROM `hulken.ads_data.shopify_orders`"
print(list(client.query(query).result())[0][0])
```

### 3.3 Tables Principales (Vérifié 2026-02-04)

| Table | Rows | Description |
|-------|------|-------------|
| shopify_orders | 585,927 | Historique complet (bulk import) |
| shopify_utm | 589,602 | Attribution UTM |
| shopify_live_orders_clean | 8,447 | Commandes récentes (hashé) |
| shopify_live_customers_clean | 10,680 | Clients (hashé) |
| facebook_insights | 159,342 | Métriques Facebook |
| tiktok_ads_reports_daily | 28,723 | Métriques TikTok |

### 3.4 Export Données

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')
query = """
SELECT order_id, total_price, first_utm_source, first_utm_campaign
FROM `hulken.ads_data.shopify_utm`
WHERE created_at >= '2026-01-01'
"""
df = client.query(query).to_dataframe()
df.to_csv('export.csv', index=False)
```

---

## 4. PII & Sécurité

### 4.1 Architecture 2 Couches

```
STAGING (PII temporaire)          CLEAN (Analytics)
─────────────────────────         ────────────────────
shopify_live_orders        →→→    shopify_live_orders_clean
shopify_live_customers     →→→    shopify_live_customers_clean
        ↓                                 ↓
    email, phone               email_hash, phone_hash
    (nullifié après hash)      (permanent)
```

### 4.2 Procédure de Hashing

```sql
-- Hash standard
TO_HEX(SHA256(LOWER(TRIM(email))))

-- Exécuter manuellement si besoin
CALL `hulken.ads_data.hash_and_nullify_pii`()
```

### 4.3 Vérification PII

```sql
-- Doit retourner 0 pour staging
SELECT
  'shopify_live_orders' as tbl,
  COUNTIF(email IS NOT NULL) as pii_exposed
FROM `hulken.ads_data.shopify_live_orders`;
```

---

## 5. Looker Studio (Dashboards)

### 5.1 Setup

1. https://lookerstudio.google.com
2. Create Data Source → BigQuery
3. Projet: hulken, Dataset: ads_data

### 5.2 Sources Recommandées

**TikTok Daily Performance:**
```sql
SELECT
  stat_time_day as date,
  campaign_name,
  SUM(spend) as spend,
  SUM(conversion) as conversions,
  SUM(total_complete_payment_rate) as purchases
FROM `hulken.ads_data.tiktok_ads_reports_daily`
GROUP BY 1, 2
```

**Facebook ROAS:**
```sql
SELECT
  date_start,
  campaign_name,
  SUM(spend) as spend,
  SUM(CAST(JSON_VALUE(actions, '$[0].value') AS FLOAT64)) as conversions
FROM `hulken.ads_data.facebook_insights`
GROUP BY 1, 2
```

---

## 6. PM2 Scheduling (UTM Extraction)

### 6.1 Configuration VM

```bash
# SSH sur la VM
gcloud compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap

# Structure
/home/Jarvis/
├── shopify_utm/
│   ├── extract_shopify_utm_incremental.py
│   ├── .env
│   └── ecosystem.config.js
```

### 6.2 Commandes PM2

```bash
pm2 list                    # Voir les processus
pm2 logs utm-extraction     # Voir les logs
pm2 restart utm-extraction  # Redémarrer
pm2 stop utm-extraction     # Arrêter
```

### 6.3 Configuration Cron (Alternative)

```bash
# Crontab actuel
0 6 * * * cd /home/Jarvis/shopify_utm && python3 extract_shopify_utm_incremental.py
```

---

## 7. Shopify Integration

### 7.1 Deux Sources de Données

| Source | Table | Rows | Période |
|--------|-------|------|---------|
| Bulk Export (JSONL) | shopify_orders | 585,927 | 2018-2026 |
| Airbyte Live | shopify_live_orders | 8,448 | 2026-02+ |
| GraphQL UTM | shopify_utm | 589,602 | Toutes |

### 7.2 Jointure Unifiée

```sql
-- Toutes les commandes avec UTM
SELECT
  o.id,
  o.total_price,
  u.first_utm_source,
  u.first_utm_campaign
FROM `hulken.ads_data.shopify_orders` o
LEFT JOIN `hulken.ads_data.shopify_utm` u ON o.id = u.order_id
```

---

## 8. Troubleshooting Global

### Authentification

| Erreur | Solution |
|--------|----------|
| `gcloud: command not found` | Réinstaller Google Cloud SDK |
| `Permission denied` | `gcloud auth login` + `gcloud auth application-default login` |
| `Project not found` | `gcloud config set project hulken` |

### BigQuery

| Erreur | Solution |
|--------|----------|
| `Access Denied` | Vérifier les permissions IAM |
| `Table not found` | Vérifier le nom: `hulken.ads_data.TABLE` |
| `Query timeout` | Ajouter `LIMIT` ou filtrer par date |

### Airbyte

| Erreur | Solution |
|--------|----------|
| `Connection refused :8000` | Relancer le tunnel SSH |
| `Sync failed` | Vérifier les credentials source |
| `Schema mismatch` | Reset de la connexion |

---

## 9. Contacts & Escalation

- **BigQuery/GCP:** Console GCP → Support
- **Airbyte:** VM logs (`docker logs airbyte-server`)
- **Shopify API:** Admin Shopify → Apps

---

*Runbook consolidé le 2026-02-04*
*Fusion de: RUNBOOK_AIRBYTE, RUNBOOK_VSCODE_BIGQUERY_SETUP, LOOKER_STUDIO_SETUP, PM2_SETUP_INSTRUCTIONS, AIRBYTE_SHOPIFY_INTEGRATION_INSTRUCTIONS*
