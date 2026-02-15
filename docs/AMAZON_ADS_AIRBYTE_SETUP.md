# Amazon Ads - Ajout à Airbyte

**Date:** 2026-02-15
**Objectif:** Ajouter Amazon Advertising comme source dans Airbyte pour syncer les données vers BigQuery

---

## 📋 Prérequis

### 1. Compte Amazon Ads

- ✅ Compte Amazon Seller Central ou Vendor Central actif
- ✅ Campagnes publicitaires Amazon actives (Sponsored Products, Sponsored Brands, etc.)
- ✅ Accès à Amazon Advertising Console: https://advertising.amazon.com

### 2. API Credentials Amazon Ads

Vous avez besoin de:
- **Client ID**
- **Client Secret**
- **Refresh Token**
- **Profile ID** (ID du compte publicitaire)
- **Region** (NA, EU, FE)

---

## 🔑 Étape 1: Obtenir les API Credentials

### A. Créer une application Amazon Ads

1. Aller sur: https://advertising.amazon.com/API/docs/en-us/setting-up/step-1-create-app
2. **Sign in** avec votre compte Amazon Seller/Vendor
3. Aller dans **Settings** → **API**
4. Cliquer **Create new application**

#### Informations à fournir:

```
Application Name: Airbyte Data Sync
Application Description: Sync Amazon Ads data to BigQuery via Airbyte
Privacy Policy URL: https://airbyte.com/privacy
Type: Confidential
Redirect URI: https://example.com/callback
```

5. **Submit** → Vous obtenez:
   - ✅ **Client ID** (quelque chose comme `amzn1.application-oa2-client.xxxxx`)
   - ✅ **Client Secret** (gardez-le secret!)

---

### B. Obtenir le Refresh Token

#### Option 1: Via outil OAuth de Amazon (Recommandé)

1. Construire l'URL d'autorisation (remplacer YOUR_CLIENT_ID):

```
https://www.amazon.com/ap/oa?client_id=YOUR_CLIENT_ID&scope=advertising::campaign_management&response_type=code&redirect_uri=https://example.com/callback
```

2. Ouvrir cette URL dans votre navigateur
3. **Sign in** et autoriser l'application
4. Vous serez redirigé vers `https://example.com/callback?code=XXXX`
5. Copier le **code** de l'URL
6. Utiliser ce code pour obtenir le refresh token via curl:

```bash
curl -X POST \
  'https://api.amazon.com/auth/o2/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=authorization_code&code=YOUR_CODE&redirect_uri=https://example.com/callback&client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET"
```

7. La réponse contient le **refresh_token**:
```json
{
  "access_token": "...",
  "refresh_token": "Atzr|...",  ← CECI
  "token_type": "bearer",
  "expires_in": 3600
}
```

#### Option 2: Via Airbyte (Plus simple)

Airbyte a un connecteur Amazon Ads qui peut gérer l'OAuth automatiquement dans certaines versions.

---

### C. Obtenir le Profile ID

1. Aller sur: https://advertising.amazon.com
2. **Sign in**
3. Ouvrir le menu déroulant en haut à droite (nom du compte)
4. Cliquer sur **Switch accounts** ou **Account settings**
5. Le **Profile ID** est affiché (format: `1234567890123`)

**Ou via API:**

```bash
curl -X GET \
  'https://advertising-api.amazon.com/v2/profiles' \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Amazon-Advertising-API-ClientId: YOUR_CLIENT_ID"
```

Réponse:
```json
[
  {
    "profileId": 1234567890123,
    "countryCode": "US",
    "currencyCode": "USD",
    "timezone": "America/Los_Angeles",
    "accountInfo": {
      "marketplaceStringId": "ATVPDKIKX0DER",
      "type": "seller"
    }
  }
]
```

---

## 🚀 Étape 2: Configurer Amazon Ads dans Airbyte

### A. Accéder à Airbyte

```bash
# Depuis votre Mac
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# Démarrer la VM (si arrêtée)
gcloud compute instances start instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a

# Créer le tunnel IAP
gcloud compute start-iap-tunnel instance-20260129-133637 8000 \
  --local-host-port=localhost:8006 \
  --zone=us-central1-a \
  --project=hulken
```

**Ouvrir:** http://localhost:8006

---

### B. Créer la Source Amazon Ads

1. Dans Airbyte, aller dans **Sources**
2. Cliquer **+ New source**
3. Chercher **"Amazon Ads"**
4. Remplir le formulaire:

```yaml
Source name: Amazon Ads - Hulken

Configuration:
  Client ID: amzn1.application-oa2-client.xxxxx
  Client Secret: [VOTRE SECRET]
  Refresh Token: Atzr|xxxxx

  Region: North America (NA)
  # Ou EU pour Europe, FE pour Far East

  Profile IDs: 1234567890123
  # Vous pouvez ajouter plusieurs IDs séparés par des virgules

  Start Date: 2024-01-01
  # Date à partir de laquelle syncer les données

  Report Wait Timeout: 30
  Report Generation Maximum Retries: 5
```

5. Cliquer **Set up source**
6. Airbyte va tester la connexion
7. Si succès ✅ → Continuer

---

### C. Créer la Connection vers BigQuery

1. Après avoir créé la source, cliquer **Set up connection**
2. **Destination:** Sélectionner `BigQuery - hulken` (existant)
3. **Streams:** Sélectionner les streams à syncer

#### Streams recommandés:

| Stream | Description | Sync Mode |
|--------|-------------|-----------|
| `sponsored_products_campaigns` | Campagnes Sponsored Products | Incremental |
| `sponsored_products_ad_groups` | Ad Groups | Incremental |
| `sponsored_products_keywords` | Mots-clés | Incremental |
| `sponsored_products_report_stream` | Métriques quotidiennes | Incremental |
| `sponsored_brands_campaigns` | Campagnes Sponsored Brands | Incremental |
| `sponsored_brands_report_stream` | Métriques Sponsored Brands | Incremental |
| `sponsored_display_campaigns` | Campagnes Display | Incremental |
| `sponsored_display_report_stream` | Métriques Display | Incremental |

4. **Sync frequency:** `Every 24 hours` (recommandé)
5. **Destination Namespace:** `ads_data`
6. **Destination Stream Prefix:** `amazon_`

7. Cliquer **Set up connection**

---

## 📊 Étape 3: Vérifier les données dans BigQuery

### A. Attendre le premier sync

- Le premier sync peut prendre 30-60 minutes (selon la quantité de données)
- Suivre la progression dans Airbyte **Job History**

### B. Vérifier les tables créées

```bash
bq ls --project_id=hulken ads_data | grep amazon
```

Résultat attendu:
```
amazon_sponsored_products_campaigns
amazon_sponsored_products_ad_groups
amazon_sponsored_products_keywords
amazon_sponsored_products_report_stream
amazon_sponsored_brands_campaigns
amazon_sponsored_brands_report_stream
...
```

### C. Compter les lignes

```sql
SELECT
  table_id,
  row_count
FROM `hulken.ads_data.__TABLES__`
WHERE table_id LIKE 'amazon_%'
ORDER BY row_count DESC;
```

---

## 📈 Étape 4: Créer amazon_ads_unified

Une fois les données synchronisées, créer une table unifiée:

```sql
CREATE OR REPLACE TABLE `hulken.ads_data.amazon_ads_unified` AS

WITH sponsored_products AS (
  SELECT
    CONCAT(CAST(date AS STRING), '_', CAST(campaign_id AS STRING)) AS amz_row_id,
    date,
    campaign_id AS amz_campaign_id,
    campaign_name AS amz_campaign_name,

    -- Metrics
    impressions AS amz_impressions,
    clicks AS amz_clicks,
    cost AS amz_spend,
    attributedConversions14d AS amz_conversions,
    attributedSales14d AS amz_sales,

    -- Calculated
    SAFE_DIVIDE(clicks, impressions) * 100 AS amz_ctr_percent,
    SAFE_DIVIDE(cost, clicks) AS amz_cpc,
    SAFE_DIVIDE(cost, impressions) * 1000 AS amz_cpm,
    SAFE_DIVIDE(attributedSales14d, cost) AS amz_roas,
    SAFE_DIVIDE(cost, NULLIF(attributedConversions14d, 0)) AS amz_cpa

  FROM `hulken.ads_data.amazon_sponsored_products_report_stream`
  WHERE date IS NOT NULL
),

sponsored_brands AS (
  SELECT
    CONCAT(CAST(date AS STRING), '_', CAST(campaign_id AS STRING), '_brand') AS amz_row_id,
    date,
    campaign_id AS amz_campaign_id,
    campaign_name AS amz_campaign_name,

    impressions AS amz_impressions,
    clicks AS amz_clicks,
    cost AS amz_spend,
    attributedConversions14d AS amz_conversions,
    attributedSales14d AS amz_sales,

    SAFE_DIVIDE(clicks, impressions) * 100 AS amz_ctr_percent,
    SAFE_DIVIDE(cost, clicks) AS amz_cpc,
    SAFE_DIVIDE(cost, impressions) * 1000 AS amz_cpm,
    SAFE_DIVIDE(attributedSales14d, cost) AS amz_roas,
    SAFE_DIVIDE(cost, NULLIF(attributedConversions14d, 0)) AS amz_cpa

  FROM `hulken.ads_data.amazon_sponsored_brands_report_stream`
  WHERE date IS NOT NULL
)

-- Combiner Sponsored Products et Brands
SELECT * FROM sponsored_products
UNION ALL
SELECT * FROM sponsored_brands;

-- Verify
SELECT
  'amazon_ads_unified' AS table_name,
  COUNT(*) AS row_count,
  SUM(amz_spend) AS total_spend,
  SUM(amz_sales) AS total_sales,
  SAFE_DIVIDE(SUM(amz_sales), SUM(amz_spend)) AS avg_roas
FROM `hulken.ads_data.amazon_ads_unified`;
```

---

## 🔄 Étape 5: Intégrer Amazon dans marketing_unified

Mettre à jour la table marketing_unified pour inclure Amazon:

```sql
-- Ajouter Amazon aux daily_ad_spend
SELECT
  date,
  'amazon' AS ad_source,
  SUM(amz_spend) AS spend,
  SUM(amz_impressions) AS impressions,
  SUM(amz_clicks) AS clicks,
  SUM(amz_sales) AS revenue
FROM `hulken.ads_data.amazon_ads_unified`
GROUP BY date

UNION ALL

-- Existing sources (Facebook, TikTok, Google)
...
```

---

## 🚨 Troubleshooting

### Erreur: "Invalid refresh token"

**Cause:** Le refresh token a expiré ou est invalide

**Solution:**
1. Refaire l'étape B (Obtenir le Refresh Token)
2. Mettre à jour la source Amazon Ads dans Airbyte avec le nouveau token

---

### Erreur: "Invalid profile ID"

**Cause:** Le Profile ID n'existe pas ou n'est pas accessible

**Solution:**
1. Vérifier le Profile ID dans Amazon Advertising Console
2. S'assurer que le compte API a accès à ce profil

---

### Erreur: "Report timeout"

**Cause:** Les rapports Amazon prennent trop de temps à générer

**Solution:**
1. Augmenter `Report Wait Timeout` à 60 dans la config Airbyte
2. Augmenter `Report Generation Maximum Retries` à 10

---

### Sync très lent

**Cause:** Beaucoup de données historiques

**Solution:**
1. Réduire la `Start Date` (par exemple: derniers 3 mois seulement)
2. Désactiver les streams peu utilisés
3. Augmenter la fréquence à "Every 24 hours" au lieu de "Every hour"

---

## 📝 Checklist finale

- [ ] Créer application Amazon Ads (Client ID + Secret)
- [ ] Obtenir Refresh Token via OAuth
- [ ] Trouver Profile ID dans Amazon Advertising Console
- [ ] Accéder à Airbyte UI (tunnel IAP)
- [ ] Créer source "Amazon Ads" dans Airbyte
- [ ] Configurer connection vers BigQuery (namespace: ads_data, prefix: amazon_)
- [ ] Sélectionner les streams (sponsored_products_report_stream minimum)
- [ ] Lancer le premier sync
- [ ] Vérifier les tables dans BigQuery
- [ ] Créer amazon_ads_unified
- [ ] Intégrer Amazon dans marketing_unified
- [ ] Tester les requêtes de ROAS

---

## 🎉 Résultat attendu

Après setup complet, vous aurez:

```sql
-- Vue d'ensemble de toutes les sources
SELECT
  channel,
  SUM(ad_spend) AS total_spend,
  SUM(revenue) AS total_revenue,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_spend)) AS roas
FROM `hulken.ads_data.marketing_unified`
GROUP BY channel
ORDER BY total_spend DESC;
```

Résultat:
```
+----------+-------------+----------------+------+
| channel  | total_spend | total_revenue  | roas |
+----------+-------------+----------------+------+
| facebook | 9,292,448   | 3,046,383      | 0.33 |
| google   | 337,871     | 1,584,252      | 4.69 |
| amazon   | 125,000     | 625,000        | 5.00 |  ← NOUVEAU
| tiktok   | 52,341      | 15,702         | 0.30 |
+----------+-------------+----------------+------+
```

