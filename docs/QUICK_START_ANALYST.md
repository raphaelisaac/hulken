# Guide Analyste - De A a Z

> Ce guide t'explique comment acceder aux donnees, lancer des requetes, verifier que tout est bon, et rafraichir les syncs.
> Prerequis : avoir un compte Google avec acces au projet GCP `hulken`.

---

## Sommaire

1. [Installation (une seule fois)](#1-installation-une-seule-fois)
2. [Acceder a BigQuery](#2-acceder-a-bigquery)
3. [Tes premieres requetes](#3-tes-premieres-requetes)
4. [Verifier les donnees (Shopify vs BigQuery)](#4-verifier-les-donnees-shopify-vs-bigquery)
5. [Les tables importantes](#5-les-tables-importantes)
6. [Lancer un rapport](#6-lancer-un-rapport)
7. [Rafraichir les donnees (syncs)](#7-rafraichir-les-donnees-syncs)
8. [Explorer avec le dashboard](#8-explorer-avec-le-dashboard)
9. [En cas de probleme](#9-en-cas-de-probleme)

---

## 1. Installation (une seule fois)

### Option A : Interface web BigQuery (rien a installer)

1. Va sur https://console.cloud.google.com/bigquery
2. Connecte-toi avec ton compte Google qui a acces au projet `hulken`
3. Dans le menu de gauche, clique sur `hulken` > `ads_data`
4. Tu vois toutes les tables. C'est pret.

**C'est la methode la plus simple pour commencer.**

### Option B : VSCode + Python (pour exports CSV et scripts)

**Windows :**
```
# 1. Installer Google Cloud SDK
#    Telecharge depuis: https://cloud.google.com/sdk/docs/install
#    Lance l'installeur, coche "Run gcloud init"

# 2. S'authentifier (une fenetre navigateur s'ouvre)
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken

# 3. Installer les packages Python
pip install google-cloud-bigquery pandas db-dtypes streamlit python-dotenv
```

**Mac :**
```bash
brew install --cask google-cloud-sdk
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken
pip3 install google-cloud-bigquery pandas db-dtypes streamlit python-dotenv
```

**Verifier que ca marche :**
```bash
python -c "from google.cloud import bigquery; c=bigquery.Client(project='hulken'); print('OK -', len(list(c.list_tables('ads_data'))), 'tables')"
```
Tu dois voir : `OK - 49 tables` (ou plus si des vues ont ete ajoutees)

---

## 2. Acceder a BigQuery

### Via l'interface web (recommande pour debuter)

1. Ouvre https://console.cloud.google.com/bigquery?project=hulken
2. Dans le panneau de gauche : `hulken` > `ads_data`
3. Clique sur une table pour voir son schema
4. Onglet "Preview" pour voir les donnees
5. Bouton "Query" en haut pour ecrire du SQL
6. Copie-colle une requete de ce guide, clique "Run"

### Via Python (pour exports et automatisation)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

# Lancer une requete
sql = "SELECT COUNT(*) as total FROM `hulken.ads_data.shopify_live_orders_clean`"
result = client.query(sql).to_dataframe()
print(result)

# Exporter en CSV
sql = "SELECT * FROM `hulken.ads_data.shopify_live_orders_clean` LIMIT 1000"
df = client.query(sql).to_dataframe()
df.to_csv('export.csv', index=False)
print(f"Exporte: {len(df)} lignes")
```

---

## 3. Tes premieres requetes

Copie-colle ces requetes dans BigQuery. Elles marchent directement.

### 3.1 Combien de commandes par jour ?

```sql
SELECT
  DATE(created_at) AS date,
  COUNT(*) AS nb_commandes,
  ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS revenu_total,
  ROUND(AVG(CAST(total_price AS FLOAT64)), 2) AS panier_moyen
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

**Resultat attendu (au 9 fev 2026) :**

| date | nb_commandes | revenu_total | panier_moyen |
|------|-------------|-------------|--------------|
| 2026-02-09 | ~195 | ~30,479 | ~156 |
| 2026-02-08 | ~756 | ~117,414 | ~155 |
| 2026-02-07 | ~716 | ~110,387 | ~154 |
| 2026-02-06 | ~597 | ~89,355 | ~150 |

> Si tu vois des chiffres proches, c'est que ta connexion fonctionne et les donnees sont la.

### 3.2 Depenses Facebook par jour

```sql
SELECT
  date_start AS date,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS depense_facebook,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clics
FROM `hulken.ads_data.facebook_ads_insights_dedup`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1
ORDER BY 1 DESC
```

> **IMPORTANT** : Utilise toujours `facebook_ads_insights_dedup` (avec _dedup). Jamais `facebook_ads_insights` directement (il y a 20% de doublons).

### 3.3 Depenses TikTok par jour

```sql
SELECT
  DATE(stat_time_day) AS date,
  ROUND(SUM(spend), 2) AS depense_tiktok,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clics
FROM `hulken.ads_data.tiktokads_reports_clean`
GROUP BY 1
ORDER BY 1 DESC
LIMIT 30
```

> On utilise `tiktokads_reports_clean` (vue simplifiee) au lieu de `tiktokads_reports_daily` (ou les metrics sont en JSON).

### 3.4 Revenue par source d'acquisition (UTM)

```sql
SELECT
  first_utm_source AS source,
  COUNT(*) AS commandes,
  ROUND(SUM(total_price), 2) AS revenu,
  ROUND(AVG(total_price), 2) AS panier_moyen
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND first_utm_source IS NOT NULL
GROUP BY 1
ORDER BY revenu DESC
```

### 3.5 Health check rapide : est-ce que tout est a jour ?

```sql
SELECT
  table_id AS table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS derniere_maj,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS heures_retard,
  row_count AS nb_lignes,
  ROUND(size_bytes / 1048576, 1) AS taille_mb
FROM `hulken.ads_data.__TABLES__`
WHERE table_id IN (
  'facebook_ads_insights',
  'tiktokads_reports_daily',
  'shopify_live_orders',
  'shopify_live_orders_clean',
  'shopify_live_customers_clean',
  'shopify_utm'
)
ORDER BY heures_retard DESC
```

**Ce qu'il faut verifier :**
- `shopify_live_orders` : < 30h de retard = OK
- `facebook_ads_insights` : < 30h = OK, > 48h = PROBLEME
- `tiktokads_reports_daily` : < 30h = OK
- `shopify_utm` : < 24h = OK

---

## 4. Verifier les donnees (Shopify vs BigQuery)

Voici comment croiser ce que tu vois dans Shopify Admin avec ce qu'il y a dans BigQuery.

### 4.1 Verifier le nombre de commandes a une date precise

**Dans Shopify Admin :** Va dans Orders, filtre par date (ex: 5 fevrier 2026), note le nombre total.

**Dans BigQuery :**
```sql
-- Nombre de commandes le 5 fevrier 2026
SELECT COUNT(*) AS nb_commandes,
  ROUND(SUM(CAST(total_price AS FLOAT64)), 2) AS revenu
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) = '2026-02-05'
```

**Le chiffre doit etre identique** (ou tres proche, decalage possible de quelques heures en fin de journee).

### 4.2 Verifier une commande specifique

Si tu as le numero de commande (ex: #BS12345) :

```sql
-- Chercher une commande par son nom
SELECT id, name, CAST(total_price AS FLOAT64) AS prix, created_at, currency
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE name = '#BS12345'
```

### 4.3 Verifier les depenses Facebook vs Facebook Ads Manager

**Dans Facebook Ads Manager :** Note la depense totale pour une campagne sur 7 jours.

**Dans BigQuery :**
```sql
-- Depenses par campagne (7 derniers jours)
SELECT
  campaign_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS depense,
  SUM(impressions) AS impressions
FROM `hulken.ads_data.facebook_ads_insights_dedup`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1
ORDER BY depense DESC
```

> Les chiffres BigQuery peuvent avoir 1-2 jours de retard par rapport a Facebook Ads Manager. C'est normal car Airbyte synce une fois par jour.

### 4.4 Verifier que le PII est bien protege

```sql
-- Verifier : pas de vrais emails, que des hash SHA-256
SELECT
  email_hash,
  LENGTH(email_hash) AS longueur_hash
FROM `hulken.ads_data.shopify_live_orders_clean`
LIMIT 5
```

**Tu dois voir** des chaines de 64 caracteres hexadecimaux, genre :
`a3f2b8c4d5e6f7...` - jamais d'email en clair.

---

## 5. Les tables importantes

### Ce que tu utilises au quotidien :

| Table | Contenu | Colonnes cles |
|-------|---------|--------------|
| `shopify_live_orders_clean` | Commandes recentes (Airbyte) | id, name, total_price, created_at, email_hash, currency |
| `shopify_live_customers_clean` | Clients (Airbyte) | id, email_hash, total_spent, orders_count |
| `shopify_utm` | Attribution UTM par commande | order_id, total_price, first_utm_source, first_utm_campaign |
| `shopify_orders` | Historique complet (585K commandes) | id, name, totalPrice, createdAt, email_hash |
| `facebook_ads_insights_dedup` | Perf Facebook (sans doublons) | campaign_name, date_start, spend, impressions, clicks |
| `tiktokads_reports_clean` | Perf TikTok (metriques extraites) | campaign_id, report_date, spend, impressions, clicks |
| `tiktokcampaigns` | Noms des campagnes TikTok | campaign_id, campaign_name |

### Ce que tu n'utilises PAS directement :

| Table | Pourquoi |
|-------|---------|
| `facebook_ads_insights` (sans _dedup) | 20% de doublons, utilise la vue _dedup |
| `tiktokads_reports_daily` | Metriques en JSON, utilise _clean |
| `shopify_live_orders` (sans _clean) | PII nullifie, pas de hash |
| `ads_insights`, `ads_insights_*` | Anciennes tables en double, ignorer |
| Toutes les tables `tiktokad_group_*`, `tiktokcampaigns_*`, `tiktokadvertisers_*` | Aggregations redondantes |

### Regles d'or :
1. **Facebook** : toujours `_dedup`
2. **TikTok** : toujours `_clean` ou extraire le JSON avec `JSON_EXTRACT_SCALAR`
3. **Shopify PII** : toujours `_clean` (jamais les tables sans _clean)
4. **Dates TikTok** : `DATE(stat_time_day)` car c'est un DATETIME pas un DATE

---

## 6. Lancer un rapport

### Rapport ROAS Facebook (par campagne)

```sql
SELECT
  u.first_utm_campaign AS campagne,
  COUNT(DISTINCT u.order_id) AS commandes,
  ROUND(SUM(u.total_price), 2) AS revenu,
  f.depense,
  ROUND(SUM(u.total_price) / NULLIF(f.depense, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT campaign_name, ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS depense
  FROM `hulken.ads_data.facebook_ads_insights_dedup`
  GROUP BY 1
) f ON u.first_utm_campaign = f.campaign_name
WHERE u.first_utm_source LIKE '%facebook%'
GROUP BY 1, f.depense
ORDER BY revenu DESC
```

### Rapport ROAS TikTok (par campagne)

```sql
SELECT
  u.first_utm_campaign AS campagne,
  COUNT(DISTINCT u.order_id) AS commandes,
  ROUND(SUM(u.total_price), 2) AS revenu,
  t.depense,
  ROUND(SUM(u.total_price) / NULLIF(t.depense, 0), 2) AS roas
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT c.campaign_name,
    ROUND(SUM(r.spend), 2) AS depense
  FROM `hulken.ads_data.tiktokads_reports_clean` r
  JOIN `hulken.ads_data.tiktokcampaigns` c ON r.campaign_id = c.campaign_id
  GROUP BY 1
) t ON u.first_utm_campaign = t.campaign_name
WHERE u.first_utm_source = 'tiktok'
GROUP BY 1, t.depense
ORDER BY revenu DESC
```

### Rapport CAC (cout d'acquisition client par canal)

```sql
SELECT
  first_utm_source AS canal,
  COUNT(DISTINCT order_id) AS nouveaux_clients,
  ROUND(SUM(total_price), 2) AS revenu_premiere_commande,
  ROUND(AVG(total_price), 2) AS panier_moyen,
  ROUND(AVG(days_to_conversion), 1) AS jours_moy_conversion
FROM `hulken.ads_data.shopify_utm`
WHERE customer_order_index = 1  -- premiere commande seulement
GROUP BY 1
ORDER BY nouveaux_clients DESC
```

### Rapport quotidien cross-platform

```sql
WITH daily_fb AS (
  SELECT date_start AS dt,
    ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS fb_spend
  FROM `hulken.ads_data.facebook_ads_insights_dedup`
  GROUP BY 1
),
daily_tt AS (
  SELECT report_date AS dt,
    ROUND(SUM(spend), 2) AS tt_spend
  FROM `hulken.ads_data.tiktokads_reports_clean`
  GROUP BY 1
),
daily_rev AS (
  SELECT DATE(created_at) AS dt,
    ROUND(SUM(total_price), 2) AS revenu,
    COUNT(*) AS commandes
  FROM `hulken.ads_data.shopify_utm`
  GROUP BY 1
)
SELECT
  r.dt AS date,
  r.commandes,
  r.revenu,
  COALESCE(f.fb_spend, 0) AS depense_facebook,
  COALESCE(t.tt_spend, 0) AS depense_tiktok,
  COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0) AS depense_totale,
  ROUND(r.revenu / NULLIF(COALESCE(f.fb_spend, 0) + COALESCE(t.tt_spend, 0), 0), 2) AS roas_global
FROM daily_rev r
LEFT JOIN daily_fb f ON r.dt = f.dt
LEFT JOIN daily_tt t ON r.dt = t.dt
WHERE r.dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY r.dt DESC
```

### Exporter un rapport en CSV (Python)

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project='hulken')

sql = """
SELECT DATE(created_at) AS date,
  COUNT(*) AS commandes,
  ROUND(SUM(total_price), 2) AS revenu
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1 ORDER BY 1
"""

df = client.query(sql).to_dataframe()
df.to_csv('rapport_revenu_30j.csv', index=False)
print(f"Exporte {len(df)} jours dans rapport_revenu_30j.csv")
```

---

## 7. Rafraichir les donnees (syncs)

### Quand rafraichir ?

Les syncs tournent automatiquement toutes les 24h via Airbyte. Tu n'as normalement rien a faire.
Lance le health check (requete 3.5 ci-dessus) pour verifier les retards.

### Si un sync est en retard (> 48h)

**Methode 1 : Via l'UI Airbyte (plus simple)**

```bash
# Terminal 1 : ouvrir le tunnel SSH vers la VM Airbyte
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap -- -L 8000:localhost:8000
```

Puis ouvre http://localhost:8000 dans ton navigateur.
- Login: `admin` / `gTafVpBcdHhBh56G`
- Tu vois les 3 connexions : Facebook, Shopify, TikTok
- Clique sur celle en retard > "Sync now"

**Methode 2 : Via script (si l'UI ne marche pas)**

```bash
# Copier le script sur la VM et l'executer
gcloud compute scp vm_scripts/trigger_all_syncs.sh Jarvis@instance-20260129-133637:/tmp/ --zone=us-central1-a --tunnel-through-iap
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --command='bash /tmp/trigger_all_syncs.sh'
```

Tu dois voir :
```
=== Getting auth token ===
Token: OK
=== Triggering syncs ===
  Facebook Marketing: job=XXX status=running
  Shopify: job=XXX status=running
  TikTok Marketing: job=XXX status=running
=== All syncs triggered ===
```

### Combien de temps ca prend ?

| Source | Duree typique | Backfill apres retard |
|--------|-------------|----------------------|
| Facebook | 15-30 min | +5 min par jour de retard |
| Shopify | 5-10 min | +2 min par jour |
| TikTok | 5-15 min | +3 min par jour |

### Le script UTM (shopify_utm) se synce separement

Il tourne sur la VM via cron toutes les heures :
```bash
# Pour verifier qu'il tourne :
gcloud compute ssh Jarvis@instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --command='crontab -l'
```

---

## 8. Explorer avec le dashboard

Un dashboard Streamlit existe pour explorer les tables visuellement.

```bash
# Depuis le dossier du projet
cd D:\Better_signal     # Windows
cd ~/Better_signal      # Mac

streamlit run data_explorer.py
```

Ca ouvre un navigateur avec :
- **Schema** : toutes les colonnes d'une table
- **Preview** : voir les 100 premieres lignes
- **Query + Export** : ecrire du SQL et telecharger en CSV
- **Overview** : toutes les tables avec taille et date

---

## 9. En cas de probleme

### "Je n'arrive pas a me connecter a BigQuery"

```bash
# Re-authentifie toi
gcloud auth login
gcloud auth application-default login
gcloud config set project hulken

# Teste
bq ls hulken:ads_data
```

Si ca ne marche toujours pas : ton compte Google n'a pas les droits sur le projet `hulken`. Demande l'acces a l'admin GCP.

### "La requete retourne 0 resultats"

1. Verifie le nom de la table (les noms TikTok sont colles : `tiktokads` pas `tiktok_ads`)
2. Verifie la plage de dates - les donnees ne remontent pas au-dela de ~6 mois
3. Lance le health check (requete 3.5) pour voir si la table a des donnees

### "Les chiffres ne correspondent pas a Shopify"

- Delai normal : jusqu'a 24h entre Shopify et BigQuery
- Les `shopify_live_*` tables sont synces par Airbyte (24h)
- La table `shopify_utm` est synce separement (horaire)
- Les commandes test (`test = true`) sont incluses - filtre avec `WHERE test = false` si besoin

### "Facebook montre X de depense mais BigQuery montre Y"

1. Verifie que tu utilises `_dedup` (sinon les doublons gonflent les chiffres)
2. Facebook Ads Manager est en temps reel, BigQuery a 24h de retard
3. La fenetre d'attribution Facebook peut faire varier les chiffres

### Scripts utiles

| Quoi | Commande |
|------|---------|
| Verifier la sante des donnees | `python data_validation/reconciliation_check.py` |
| Dashboard d'exploration | `streamlit run data_explorer.py` |
| Relancer tous les syncs | Voir section 7 |

---

## Aide-memoire

```
Projet GCP      : hulken
Dataset          : ads_data
Commandes        : shopify_live_orders_clean  (ou shopify_orders pour historique)
Clients          : shopify_live_customers_clean
Attribution      : shopify_utm
Facebook         : facebook_ads_insights_dedup  (TOUJOURS avec _dedup)
TikTok           : tiktokads_reports_clean  (ou tiktokads_reports_daily + JSON)
Campagnes TikTok : tiktokcampaigns
VM Airbyte       : instance-20260129-133637 (zone us-central1-a)
```
