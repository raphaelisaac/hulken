# Data Map - Better Signal / Hulken

> Projet GCP : `hulken` | 5 datasets | ~170 tables | Derniere mise a jour : 8 fev 2026

---

## Vue d'ensemble

```
SHOPIFY (API REST + GraphQL)
  └── Airbyte ──→ shopify_live_orders/customers/products/transactions/refunds
  └── Airbyte ──→ shopify_orders, shopify_line_items (GraphQL historique)
  └── Script Python (cron VM) ──→ shopify_utm
  └── Scheduled Query BQ (5 min) ──→ *_clean (PII hashe)

FACEBOOK ADS (API Marketing)
  └── Airbyte ──→ facebook_ads_insights, _region, _country, _age_and_gender
  └── Airbyte ──→ facebook_ads, facebook_ad_creatives, facebook_ad_sets
  └── Airbyte (ancien connecteur) ──→ ads_insights_*, ads, ad_creatives, ad_sets

TIKTOK ADS (API Marketing)
  └── Airbyte ──→ tiktokads_reports_daily, audience_reports_*
  └── Airbyte ──→ tiktokad_groups_*, tiktokcampaigns_*, tiktokadvertisers_*
  └── Airbyte ──→ tiktokads, tiktokad_groups, tiktokcampaigns

GOOGLE ANALYTICS 4 (Integration native GA4 → BigQuery)
  └── GA4 EU (334792038) ──→ events_*, pseudonymous_users_*, users_*
  └── GA4 US (454869667) ──→ events_*, pseudonymous_users_*, users_*
  └── GA4 CA (454871405) ──→ events_*, pseudonymous_users_*, users_*

GOOGLE ADS : PAS CONNECTE
```

---

## Dataset 1 : `ads_data` (47 tables)

Le dataset principal. Toutes les donnees business arrivent ici.

### Shopify - Commandes (via Airbyte, API REST)

| Table | Lignes | Source | Description |
|-------|--------|--------|-------------|
| `shopify_live_orders` | 9,865 | Airbyte → API REST Shopify | Commandes brutes, 101 colonnes. **Contient du PII** - ne pas utiliser directement |
| `shopify_live_orders_clean` | 9,865 | Scheduled Query BQ (toutes les 5 min) | **Table a utiliser.** Copie nettoyee : emails hashes en SHA256, noms supprimes, JSON customer scrub |
| `shopify_orders` | 585,927 | Airbyte → API GraphQL Shopify | Historique complet des commandes (16 colonnes, remonte plus loin dans le temps). Flux different du live |
| `shopify_line_items` | 719,124 | Airbyte → API GraphQL Shopify | Detail produit de chaque commande : quel article, quelle quantite, quel prix unitaire, quel variant |

### Shopify - Clients (via Airbyte, API REST)

| Table | Lignes | Source | Description |
|-------|--------|--------|-------------|
| `shopify_live_customers` | 13,350 | Airbyte → API REST Shopify | Clients bruts. **Contient du PII** - ne pas utiliser directement |
| `shopify_live_customers_clean` | 13,350 | Scheduled Query BQ (toutes les 5 min) | **Table a utiliser.** Emails hashes, first_name hashe (colonne `first_name_hash`), total depense, nb commandes |

### Shopify - Produits, Transactions, Remboursements (via Airbyte)

| Table | Lignes | Source | Description |
|-------|--------|--------|-------------|
| `shopify_live_products` | 942 | Airbyte → API REST Shopify | Catalogue produits : nom, prix, variantes, images, statut |
| `shopify_live_transactions` | 31,750 | Airbyte → API REST Shopify | Transactions de paiement : montant, gateway (Shopify Payments, PayPal...), statut |
| `shopify_live_order_refunds` | 349 | Airbyte → API REST Shopify | Remboursements : montant, raison, articles rembourses, date |

### Shopify - Attribution UTM (via script Python custom)

| Table | Lignes | Source | Description |
|-------|--------|--------|-------------|
| `shopify_utm` | 592,091 | Script Python sur VM (`extract_shopify_utm_incremental.py`, cron quotidien) | Attribution marketing de chaque commande. Extrait via GraphQL `customerJourneySummary`. Contient : `first_utm_source`, `first_utm_medium`, `first_utm_campaign`, `first_utm_content`, `first_utm_term`, `first_landing_page`, `first_referrer_url`, `last_utm_source/medium/campaign`, `sales_channel`, `attribution_status`. Zero doublons garanti (staging + MERGE) |

### Facebook Ads - Connecteur actuel (via Airbyte)

Donnees provenant de l'**API Facebook Marketing**. 3 ad accounts (US, EU, CA).

> **IMPORTANT** : `facebook_ads_insights` contient ~33,000 doublons a cause du mode append d'Airbyte. Toujours utiliser le pattern de deduplication :
> ```sql
> WITH deduped AS (
>   SELECT *, ROW_NUMBER() OVER (
>     PARTITION BY ad_id, date_start
>     ORDER BY _airbyte_extracted_at DESC
>   ) AS rn
>   FROM `hulken.ads_data.facebook_ads_insights`
> )
> SELECT * FROM deduped WHERE rn = 1
> ```

| Table | Lignes | Description |
|-------|--------|-------------|
| `facebook_ads_insights` | 159,342 | **Metriques principales** par ad par jour : spend, impressions, clicks, reach, conversions, actions, cost_per_action. Cle : `ad_id` + `date_start` |
| `facebook_ads_insights_age_and_gender` | 1,494,810 | Memes metriques ventilees par tranche d'age (18-24, 25-34...) et genre (male, female, unknown) |
| `facebook_ads_insights_region` | 911,412 | Metriques ventilees par region/etat (California, New York, Ile-de-France...) |
| `facebook_ads_insights_country` | 332,442 | Metriques ventilees par pays (US, FR, CA, UK...) |
| `facebook_ads` | 5,428 | Catalogue des publicites : nom, statut (ACTIVE/PAUSED), date creation, ad_set_id, campaign_id |
| `facebook_ad_creatives` | 5,160 | Contenu creatif des pubs : texte du post, image/video URL, lien destination, call-to-action |
| `facebook_ad_sets` | 341 | Ad Sets : budget quotidien/lifetime, ciblage (age, interets, geo), placement (feed, stories, reels), scheduling |

### Facebook Ads - Ancien connecteur (via Airbyte, legacy)

Memes donnees que ci-dessus mais extraites par un ancien connecteur Airbyte avec un format de colonnes different. **Gardees pour l'historique** - utiliser les tables `facebook_*` pour les analyses recentes.

| Table | Lignes | Description |
|-------|--------|-------------|
| `ads_insights` | 33,433 | Equivalent ancien de `facebook_ads_insights` |
| `ads_insights_age_and_gender` | 245,941 | Par age et genre |
| `ads_insights_country` | 105,734 | Par pays |
| `ads_insights_region` | 704,120 | Par region |
| `ads_insights_dma` | 26,415 | Par DMA (Designated Market Area - zones marketing US type "New York Metro") |
| `ads_insights_platform_and_device` | 467,829 | Par plateforme (Facebook, Instagram, Messenger, Audience Network) et device (mobile, desktop) |
| `ads_insights_action_type` | 33,434 | Par type d'action (purchase, add_to_cart, view_content, initiate_checkout, lead, link_click...) |
| `ads` | 1,172 | Ancien catalogue pubs |
| `ad_creatives` | 3,483 | Ancien creatifs |
| `ad_sets` | 62 | Ancien ad sets |
| `images` | 342 | Images utilisees dans les pubs |

### TikTok Ads (via Airbyte)

Donnees provenant de l'**API TikTok Marketing**. Un seul advertiser ID (`7109416173220986881`).

Les metriques TikTok sont stockees dans une **colonne JSON `metrics`** qu'il faut extraire :
```sql
SELECT
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.spend') AS FLOAT64) AS spend,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.impressions') AS INT64) AS impressions,
  CAST(JSON_EXTRACT_SCALAR(metrics, '$.clicks') AS INT64) AS clicks
FROM `hulken.ads_data.tiktokads_reports_daily`
```

**Niveau Ad (publicite individuelle) :**

| Table | Lignes | Description |
|-------|--------|-------------|
| `tiktokads_reports_daily` | 30,287 | **Metriques principales** par ad par jour : spend, impressions, clicks, conversions (dans JSON `metrics`) |
| `tiktokads_audience_reports_daily` | 230,288 | Metriques par audience (age, genre) par jour |
| `tiktokads_audience_reports_by_province_daily` | 1,052,020 | Metriques par province/region |
| `tiktokads_audience_reports_by_country_daily` | 33,383 | Metriques par pays |
| `tiktokads_audience_reports_by_platform_daily` | 89,294 | Metriques par plateforme (iOS, Android, desktop) |
| `tiktokads_reports_by_country_daily` | 34,444 | Reports ad par pays |
| `tiktokads` | 854 | Catalogue des pubs TikTok : nom, statut, creatif, date creation |

**Niveau Ad Group (groupe de ciblage) :**

| Table | Lignes | Description |
|-------|--------|-------------|
| `tiktokad_groups_reports_daily` | 6,673 | Metriques par ad group par jour |
| `tiktokad_groups_reports_by_country_daily` | 7,250 | Ad group par pays |
| `tiktokad_group_audience_reports_daily` | 53,813 | Audience par ad group |
| `tiktokad_group_audience_reports_by_platform_daily` | 19,751 | Audience ad group par plateforme |
| `tiktokad_group_audience_reports_by_country_daily` | 6,863 | Audience ad group par pays |
| `tiktokad_groups` | 71 | Catalogue ad groups : ciblage, budget, placement |

**Niveau Campaign :**

| Table | Lignes | Description |
|-------|--------|-------------|
| `tiktokcampaigns_reports_daily` | 5,777 | Metriques par campagne par jour |
| `tiktokcampaigns_audience_reports_daily` | 50,725 | Audience par campagne |
| `tiktokcampaigns_audience_reports_by_platform_daily` | 17,852 | Audience campagne par plateforme |
| `tiktokcampaigns_audience_reports_by_country_daily` | 6,109 | Audience campagne par pays |
| `tiktokcampaigns` | 35 | Catalogue campagnes : nom, objectif (CONVERSIONS, TRAFFIC...), budget |

**Niveau Advertiser (compte total) :**

| Table | Lignes | Description |
|-------|--------|-------------|
| `tiktokadvertisers_reports_daily` | 1,331 | Metriques totales du compte par jour |
| `tiktokadvertisers_audience_reports_daily` | 17,315 | Audience totale par jour |
| `tiktokadvertisers_audience_reports_by_platform_daily` | 4,982 | Audience par plateforme |
| `tiktokadvertisers_audience_reports_by_country_daily` | 1,785 | Audience par pays |

---

## Dataset 2 : `analytics_334792038` - Google Analytics 4 (EU)

**Source** : Integration native GA4 → BigQuery (pas Airbyte). Export automatique quotidien configure dans la console GA4.
**Propriete GA4** : Site web Hulken **Europe**
**Volume** : ~160,000 - 237,000 events par jour
**Tables** : ~40 (nouvelles tables chaque jour)

| Type de table | Pattern | Exemple | Description |
|---------------|---------|---------|-------------|
| Events quotidiens | `events_YYYYMMDD` | `events_20260206` | Tous les evenements du site : `page_view`, `purchase`, `add_to_cart`, `session_start`, `begin_checkout`, `view_item`, `click`, `scroll`, `first_visit`. Une ligne = un evenement avec timestamp, user_pseudo_id, parametres |
| Events temps reel | `events_intraday_YYYYMMDD` | `events_intraday_20260208` | Memes donnees mais pour **aujourd'hui** - pas encore finalisees, mises a jour en continu. Remplacees par la table daily le lendemain |
| Utilisateurs anonymes | `pseudonymous_users_YYYYMMDD` | `pseudonymous_users_20260206` | Profils utilisateurs anonymes (identifies par cookie/client_id). Comportement cross-session, proprietes utilisateur, segments d'audience |
| Utilisateurs identifies | `users_YYYYMMDD` | `users_20260206` | Utilisateurs logues/identifies. Proprietes user, user_id, derniere activite |

**Colonnes cles dans `events_*` :**
- `event_name` : type d'evenement (page_view, purchase, add_to_cart...)
- `event_timestamp` : timestamp en microsecondes
- `user_pseudo_id` : identifiant anonyme (cookie)
- `event_params` : RECORD avec les parametres (page_location, page_title, value, currency...)
- `traffic_source` : source, medium, campaign du premier touch
- `device` : category, browser, operating_system, language
- `geo` : country, region, city

---

## Dataset 3 : `analytics_454869667` - Google Analytics 4 (US)

**Source** : Integration native GA4 → BigQuery
**Propriete GA4** : Site web Hulken **USA**
**Volume** : ~10,000 - 19,000 events par jour (plus petit que EU)
**Tables** : ~40

Meme structure que le dataset EU : `events_YYYYMMDD`, `events_intraday_YYYYMMDD`, `pseudonymous_users_YYYYMMDD`, `users_YYYYMMDD`.

---

## Dataset 4 : `analytics_454871405` - Google Analytics 4 (CA)

**Source** : Integration native GA4 → BigQuery
**Propriete GA4** : Site web Hulken **Canada**
**Volume** : ~150,000 - 228,000 events par jour (gros volume, similaire a EU)
**Tables** : ~40

Meme structure que EU et US.

---

## Dataset 5 : `airbyte_internal` (15 tables)

**Source** : Cree automatiquement par Airbyte
**Usage** : Tables internes de gestion des syncs. **Ne pas modifier.**

Contient les curseurs de pagination, checksums, et etat des syncs pour chaque table synchronisee. Airbyte s'en sert pour savoir ou reprendre quand un sync s'arrete ou redemarre. Les noms de tables sont des hash (ex: `ads_dataads_insights8b8754ab2c6d45382f92c2e36de053c7`).

---

## Protection PII

Les donnees personnelles sont protegees par un systeme a 2 couches :

1. **Airbyte** sync les donnees brutes dans les tables `shopify_live_*` (contiennent du PII)
2. **Scheduled Query** `sync_and_hash_pii()` tourne toutes les **5 minutes** :
   - Copie dans les tables `*_clean`
   - Hash les emails : `TO_HEX(SHA256(LOWER(TRIM(email))))` → colonne `email_hash`
   - Hash les noms : `first_name` → `first_name_hash`
   - Supprime tous les champs PII en clair (email, first_name, last_name, phone, address, customer JSON)
   - Nullifie le PII dans les tables staging

**Regles** :
- Toujours utiliser `shopify_live_orders_clean` et `shopify_live_customers_clean`
- Jamais `shopify_live_orders` ou `shopify_live_customers` directement
- Le matching cross-table se fait via `email_hash` (64 caracteres, SHA256)

---

## Fraicheur des donnees

| Source | Methode de sync | Frequence | Retard typique |
|--------|----------------|-----------|----------------|
| Shopify (live) | Airbyte cron | Horaire | < 2h |
| Shopify (orders GraphQL) | Airbyte cron | Quotidien | < 24h |
| Shopify UTM | Script Python cron | Quotidien | < 24h |
| Facebook Ads | Airbyte cron | Quotidien | 1-2 jours (API Facebook a du retard natif) |
| TikTok Ads | Airbyte cron | Quotidien | 1-2 jours |
| Google Analytics 4 | Integration native | Quotidien + intraday | Daily = J+1, Intraday = quelques heures |
| PII hashing | Scheduled Query BQ | Toutes les 5 min | < 5 min |

---

## Ce qui manque

| Source | Statut | Action requise |
|--------|--------|----------------|
| Google Ads | **PAS CONNECTE** | Configurer OAuth dans Google Ads UI, obtenir developer_token et customer_ids, creer connecteur Airbyte |
| Microsoft/Bing Ads | Pas configure | A evaluer si utilise |
| Pinterest Ads | Pas configure | A evaluer si utilise |
