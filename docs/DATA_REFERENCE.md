# Data Reference - Hulken BigQuery

**Dernière mise à jour:** 2026-02-04
**Projet:** hulken
**Dataset:** ads_data
**Total Tables:** 65

---

## 1. Vue d'Ensemble

### Sources de Données

| Source | Tables | Rows Total | Sync |
|--------|--------|------------|------|
| Shopify (Bulk) | 2 | 585,927 | One-time |
| Shopify (Airbyte) | 7 | ~30,000 | Horaire |
| Shopify (GraphQL UTM) | 1 | 589,602 | Daily |
| Facebook Marketing | 16 | 159,342 | Horaire |
| TikTok Marketing | 24 | 28,723+ | Horaire |
| GA4 | 3 datasets | External | - |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SOURCES                                   │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   SHOPIFY    │   FACEBOOK   │   TIKTOK     │     GA4        │
└──────┬───────┴──────┬───────┴──────┬───────┴────────┬───────┘
       │              │              │                │
       ▼              ▼              ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                    BigQuery: hulken.ads_data                 │
├─────────────────────────────────────────────────────────────┤
│  shopify_orders (585K)  │  facebook_ads_insights (159K)     │
│  shopify_utm (589K)     │  tiktokads_reports_daily (28K)    │
│  shopify_live_* (8K)    │  + 55 autres tables               │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Tables Shopify

### 2.1 shopify_orders (Bulk Import)

**Rows:** 585,927 | **Période:** 2018-03 → 2026-01-29

| Colonne | Type | Description | PII |
|---------|------|-------------|-----|
| id | STRING | ID GraphQL (gid://shopify/Order/xxx) | - |
| name | STRING | Numéro commande (#1001) | - |
| email_hash | STRING | SHA256(email) | Hash |
| created_at | TIMESTAMP | Date création | - |
| total_price | NUMERIC | Montant total | - |
| currency | STRING | Devise (EUR, USD) | - |
| financial_status | STRING | paid, refunded, etc. | - |
| fulfillment_status | STRING | fulfilled, partial, null | - |
| shipping_country | STRING | Pays livraison | - |

### 2.2 shopify_utm (GraphQL Extraction)

**Rows:** 589,602 | **Sync:** Daily 6h UTC

| Colonne | Type | Description |
|---------|------|-------------|
| order_id | STRING | ID commande |
| created_at | TIMESTAMP | Date commande |
| total_price | FLOAT | Montant |
| first_utm_source | STRING | facebook, google, tiktok, etc. |
| first_utm_medium | STRING | cpc, paid, organic |
| first_utm_campaign | STRING | Nom campagne |
| first_utm_content | STRING | Variante pub |
| sales_channel | STRING | online_store, amazon, etc. |
| attribution_status | STRING | HAS_UTM, NO_UTM, AMAZON |

### 2.3 shopify_live_orders (Airbyte)

**Rows:** 8,448 | **Sync:** Horaire

| Colonne | Type | Description | PII |
|---------|------|-------------|-----|
| id | INTEGER | ID numérique | - |
| email | STRING | **NULLIFIÉ** après sync | ~~PII~~ |
| phone | STRING | **NULLIFIÉ** après sync | ~~PII~~ |
| total_price | NUMERIC | Montant | - |
| line_items | JSON | Produits commandés | - |
| shipping_address | JSON | **NULLIFIÉ** | ~~PII~~ |

### 2.4 shopify_live_orders_clean (Post-Hash)

**Rows:** 8,447 | **100% avec hash**

| Colonne | Type | Description |
|---------|------|-------------|
| email_hash | STRING | SHA256(LOWER(TRIM(email))) |
| phone_hash | STRING | SHA256(phone) |
| *(autres colonnes identiques à shopify_live_orders)* |

### 2.5 shopify_live_customers_clean

**Rows:** 10,680 | **100% avec hash**

| Colonne | Type | Description |
|---------|------|-------------|
| id | INTEGER | ID client |
| email_hash | STRING | SHA256(email) |
| orders_count | INTEGER | Nombre commandes |
| total_spent | NUMERIC | Dépenses totales |
| created_at | TIMESTAMP | Date création compte |

---

## 3. Tables Facebook

### 3.1 facebook_ads_insights (Principal)

**Rows:** 159,342 | **Sync:** Horaire

| Colonne | Type | Description |
|---------|------|-------------|
| date_start | DATE | Date |
| campaign_id | STRING | ID campagne |
| campaign_name | STRING | Nom campagne |
| adset_name | STRING | Nom ad set |
| ad_name | STRING | Nom pub |
| spend | FLOAT | Dépense (€) |
| impressions | INTEGER | Impressions |
| clicks | INTEGER | Clics |
| reach | INTEGER | Portée |
| actions | JSON | Conversions (voir structure) |
| action_values | JSON | Valeurs conversions |

**Structure JSON actions:**
```json
[
  {"action_type": "purchase", "value": "5"},
  {"action_type": "add_to_cart", "value": "12"}
]
```

### 3.2 Autres Tables Facebook

| Table | Description |
|-------|-------------|
| facebook_campaigns | Métadonnées campagnes |
| facebook_ad_sets | Métadonnées ad sets |
| facebook_ads | Métadonnées pubs |
| facebook_ads_insights_country | Métriques par pays |
| facebook_ads_insights_age_and_gender | Métriques démographiques |

---

## 4. Tables TikTok

### 4.1 tiktokads_reports_daily (Principal)

**Rows:** 28,723 | **Sync:** Horaire

| Colonne | Type | Description |
|---------|------|-------------|
| stat_time_day | DATE | Date |
| campaign_id | STRING | ID campagne |
| campaign_name | STRING | Nom campagne |
| adgroup_id | STRING | ID ad group |
| ad_id | STRING | ID pub |
| spend | FLOAT | Dépense ($) |
| impressions | INTEGER | Impressions |
| clicks | INTEGER | Clics |
| conversion | INTEGER | Conversions |
| total_complete_payment_rate | FLOAT | Taux achat |
| metrics | JSON | Métriques détaillées |

### 4.2 Autres Tables TikTok

| Table | Description |
|-------|-------------|
| tiktokcampaigns | Métadonnées campagnes |
| tiktokads | Métadonnées pubs |
| tiktokads_reports_by_country_daily | Par pays |
| tiktokads_audience_reports_daily | Audiences |

---

## 5. Liaisons Cross-Platform

### 5.1 Matrice de Jointure

| De → Vers | Clé | Exemple |
|-----------|-----|---------|
| shopify_utm → shopify_orders | order_id | Attribution |
| shopify_utm → facebook_ads_insights | utm_campaign = campaign_name | ROAS |
| shopify_utm → tiktokads_reports_daily | utm_campaign LIKE campaign_id | ROAS |
| shopify_orders → shopify_live_customers_clean | email_hash | LTV |

### 5.2 Ce qui N'EST PAS Possible

❌ **Lier email_hash Shopify ↔ utilisateur Facebook/TikTok**
- Les APIs Ads ne fournissent pas les emails individuels
- Seules les métriques agrégées sont disponibles

### 5.3 Exemple ROAS Cross-Platform

```sql
SELECT
  u.first_utm_source as platform,
  COUNT(DISTINCT u.order_id) as orders,
  SUM(u.total_price) as revenue,
  SUM(CASE
    WHEN u.first_utm_source = 'facebook' THEN f.spend
    WHEN u.first_utm_source = 'tiktok' THEN t.spend
  END) as spend
FROM `hulken.ads_data.shopify_utm` u
LEFT JOIN (
  SELECT campaign_name, SUM(spend) as spend
  FROM `hulken.ads_data.facebook_ads_insights`
  GROUP BY 1
) f ON u.first_utm_campaign = f.campaign_name
LEFT JOIN (
  SELECT campaign_name, SUM(spend) as spend
  FROM `hulken.ads_data.tiktokads_reports_daily`
  GROUP BY 1
) t ON u.first_utm_campaign = t.campaign_name
WHERE u.first_utm_source IN ('facebook', 'tiktok')
GROUP BY 1
```

---

## 6. PII Classification

### 6.1 Champs PII par Table

| Table | Champ | Traitement |
|-------|-------|------------|
| shopify_live_orders | email | NULLIFIÉ |
| shopify_live_orders | phone | NULLIFIÉ |
| shopify_live_orders | browser_ip | NULLIFIÉ |
| shopify_live_orders | billing_address | NULLIFIÉ |
| shopify_live_orders | shipping_address | NULLIFIÉ |
| shopify_live_customers | email | NULLIFIÉ |
| shopify_live_customers | first_name | NULLIFIÉ |
| shopify_live_customers | last_name | NULLIFIÉ |
| shopify_live_customers | addresses | NULLIFIÉ |

### 6.2 Hash Standard

```sql
-- Formule utilisée partout
TO_HEX(SHA256(LOWER(TRIM(field))))

-- Recherche par email connu
SELECT * FROM `hulken.ads_data.shopify_orders`
WHERE email_hash = TO_HEX(SHA256(LOWER(TRIM('customer@example.com'))))
```

---

## 7. GA4 (Externe)

### Datasets Disponibles

| Dataset | Property ID | Description |
|---------|-------------|-------------|
| analytics_334792038 | 334792038 | Hulken EU |
| analytics_454869667 | 454869667 | Hulken US |
| analytics_454871405 | 454871405 | Hulken CA |

### Tables Principales

- `events_*` - Événements (partitionné par jour)
- `events_intraday_*` - Événements temps réel
- `pseudonymous_users_*` - Utilisateurs pseudo

---

## 8. Vérifications Data Quality

### Fraîcheur des Données

```sql
SELECT
  'shopify_live_orders' as source,
  MAX(_airbyte_extracted_at) as last_sync
FROM `hulken.ads_data.shopify_live_orders`
UNION ALL
SELECT 'facebook_ads_insights', MAX(_airbyte_extracted_at)
FROM `hulken.ads_data.facebook_ads_insights`
UNION ALL
SELECT 'tiktokads_reports_daily', MAX(_airbyte_extracted_at)
FROM `hulken.ads_data.tiktokads_reports_daily`
```

### Doublons

```sql
SELECT order_id, COUNT(*) as cnt
FROM `hulken.ads_data.shopify_utm`
GROUP BY 1
HAVING cnt > 1
```

---

*Référence consolidée le 2026-02-04*
*Fusion de: BIGQUERY_TABLES_REFERENCE, DATA_DICTIONARY, DATA_INVENTORY*
