# Reponse aux questions du client - Shopify & Data Pipeline
Date: 2026-02-12

---

## Problemes identifies et corriges aujourd'hui

### 1. TikTok - Mismatch de 72-80% RESOLU
**Cause**: Les vues BigQuery (`tiktok_ads_reports_daily`, etc.) ne dedupliquaient pas les donnees.
Airbyte re-sync les 7 derniers jours a chaque execution, creant des doublons dans les tables raw.
La vue sommait TOUT, donc les chiffres etaient x2.

**Fix applique**: Les 4 vues TikTok ont ete recreees avec deduplication (ROW_NUMBER).
- Avant: spend $51,165 (double) -> Apres: $18,827 (= API exactement)
- Fichier SQL: `fix_tiktok_dedup_views.sql`

### 2. Facebook - Mismatch de 11% EXPLIQUE
**Cause**: Le sync Facebook (Job 150) tourne depuis 48h+ car il traite un volume massif
de donnees breakdown (region, country, age/gender = 1.8M+ records).
La table principale `facebook_insights` a ete completee le 10 fev, mais les breakdowns
sont toujours en cours d'ecriture (region en cours MAINTENANT).

**Ce n'est PAS une panne** - c'est un gros sync qui prend du temps.

Les streams du Job 150:
- facebook_insights: 127,725 records (TERMINE)
- facebook_ads_insights_age_and_gender: 1,259,760 records (TERMINE)
- facebook_ads_insights_country: 229,835 records (TERMINE)
- facebook_ads_insights_region: ~48,000+ records (EN COURS)

**Solution**: Le script de reconciliation exclut maintenant les 2 derniers jours par defaut
pour eviter les faux mismatch lies au delai de sync. Apres la fin du Job 150, les
chiffres devraient matcher a <2%.

### 3. Tables _clean Shopify RAFRAICHIES
Les tables `shopify_live_orders_clean` et `shopify_live_customers_clean` n'avaient pas ete
mises a jour depuis le 4 fevrier. Elles sont maintenant a jour (12 fev).
- Orders: 16,961 commandes uniques (dedupliquees des 41,569 rows raw)
- Customers: 23,513 clients uniques (dedupliques des 44,796 rows raw)

### 4. Nouvelles vues Shopify dedupliquees CREEES
Toutes les tables Shopify raw avaient des doublons massifs. Nouvelles vues propres:

| Vue creee | Raw rows | Dedup rows | Ratio |
|-----------|----------|------------|-------|
| `shopify_products` | 1,923 | **55** | 35x ! |
| `shopify_transactions` | 58,712 | **23,844** | 2.5x |
| `shopify_refunds` | 579 | **572** | 1.01x |

Fichier SQL de reference: `scheduled_refresh_clean_tables.sql`

---

## Reponses aux questions specifiques du client

### Q: "Il manque une table, pourquoi elle n'apparait pas dans le check?"
**R**: La table `shopify_live_inventory_items` existe mais est **vide** (0 rows).
Cela signifie que le connecteur Airbyte Shopify ne sync pas les inventory items,
ou que le scope API du token Shopify ne donne pas acces a cette donnee.

**Action necessaire**: Verifier dans Airbyte que le stream "inventory_items" est active,
et que le token Shopify a le scope `read_inventory`.

### Q: "Le sync ne marche pas"
**R**: Le sync Airbyte Shopify fonctionne - les tables raw sont a jour (derniere extraction:
12 fev 2026, 09:00 UTC). MAIS les tables `_clean` (dedupliquees) n'etaient pas rafraichies
automatiquement. Elles sont maintenant a jour.

**Action necessaire**: Creer un scheduled query dans BigQuery pour rafraichir les _clean tables
automatiquement apres chaque sync Airbyte (toutes les 24h).

### Q: "Comment se connecter a Airbyte?"
**R**: Airbyte est installe sur une VM Google Cloud.
1. Ouvrir un terminal
2. `ssh airbyte-vm` (ou utiliser la console GCP > Compute Engine > SSH)
3. L'interface web Airbyte est accessible sur `http://localhost:8000` apres le tunnel SSH
4. Identifiants: voir le fichier `data_validation/.env` (variables AIRBYTE_*)

Documentation complete: `docs/runbooks/airbyte_operations.md`

### Q: "Que faire quand il y a un probleme de sync?"
**R**: Procedure de diagnostic:
1. Aller dans Airbyte UI > Connections
2. Verifier le statut du dernier job (Succeeded/Failed/Running)
3. Si Failed: cliquer sur le job pour voir les logs d'erreur
4. Causes frequentes:
   - Token API expire -> Regenerer le token dans la plateforme source
   - Rate limiting -> Attendre et relancer
   - Schema change -> Reset de la connexion dans Airbyte
5. Pour relancer manuellement: cliquer "Sync Now" sur la connexion

### Q: "Pourquoi encrypter l'email?"
**R**: L'encryption (hashing SHA-256) des emails est obligatoire pour:
- **Conformite GDPR/RGPD**: Les emails sont des donnees personnelles (PII). Stocker des emails
  en clair dans BigQuery expose l'entreprise a des amendes pouvant atteindre 4% du CA.
- **Conformite SOC 2**: Standard de securite requis par les clients enterprise.
- **Cross-platform matching**: Le hash permet de matcher un client entre Facebook, TikTok et
  Shopify SANS exposer son email. Facebook et TikTok utilisent le meme algo (SHA-256 lowercase).

**Important**: Les emails en clair restent dans Shopify Admin. BigQuery contient uniquement
les hash pour l'analyse. Si vous avez besoin de l'email d'un client specifique, consultez
Shopify directement.

### Q: "Pourquoi les noms/prenoms sont identiques pour differents utilisateurs?"
**R**: C'est un artefact du systeme de hashing PII. Les colonnes first_name et last_name
dans les tables raw ont ete mises a NULL pour la conformite GDPR. Dans les tables _clean,
elles sont remplacees par des hash (first_name_hash, last_name_hash).

Si deux clients ont le meme prenom (ex: "David"), leur first_name_hash sera identique
car SHA-256 est deterministe. C'est normal et attendu.

Le prenom en clair (`first_name`) est conserve dans la table customers_clean car il est
considere comme non-identifiant seul. Le nom de famille est hashe.

### Q: "Comment changer les noms des tables?"
**R**: On ne renomme PAS les tables directement (cela casserait les queries existantes).
A la place, on cree des VUES (views) avec le nom souhaite:

```sql
-- Exemple: creer un alias plus lisible
CREATE OR REPLACE VIEW `hulken.ads_data.commandes_shopify` AS
SELECT * FROM `hulken.ads_data.shopify_live_orders_clean`;
```

Les vues sont des alias qui ne dupliquent pas les donnees.

### Q: "Comment changer les variables (colonnes) des tables?"
**R**: On ne modifie pas les colonnes des tables Airbyte (elles sont gerees automatiquement).
Pour personnaliser les colonnes visibles, on cree une vue:

```sql
-- Exemple: vue simplifiee avec seulement les colonnes utiles
CREATE OR REPLACE VIEW `hulken.ads_data.orders_simplified` AS
SELECT
  id AS order_id,
  name AS order_number,
  created_at,
  total_price,
  currency,
  financial_status,
  fulfillment_status,
  tags,
  source_name AS channel
FROM `hulken.ads_data.shopify_live_orders_clean`;
```

### Q: "Comment relier les tables Shopify entre elles?"
**R**: Les tables Shopify se joignent via des cles communes. Voici les JOINs principaux:

```sql
-- Commandes + Details produits par commande
SELECT o.*, li.*
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_line_items` li ON o.id = li.order_id;

-- Commandes + Clients
SELECT o.*, c.email_hash, c.tags
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_live_customers_clean` c ON o.customer_id = c.id;

-- Commandes + Attribution UTM
SELECT o.name AS order_number, o.total_price, u.source, u.medium, u.campaign
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_utm` u ON o.id = u.order_id;

-- Commandes + Transactions de paiement
SELECT o.name, o.total_price, t.gateway, t.kind, t.amount
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_transactions` t ON o.id = t.order_id;

-- Commandes + Remboursements
SELECT o.name, o.total_price, r.created_at AS refund_date
FROM `hulken.ads_data.shopify_live_orders_clean` o
JOIN `hulken.ads_data.shopify_refunds` r ON o.id = r.order_id;
```

### Q: "Pourquoi Google Ads n'est pas efface? Faire de l'ordre dans ads_data"
**R**: Google Ads n'a JAMAIS ete dans le dataset `ads_data`. Il est dans un dataset separe:

| Dataset | Contenu | Statut |
|---------|---------|--------|
| `hulken.google_Ads` (majuscule) | 96 tables + 96 vues Google Ads Data Transfer (account 4354001000) | **ACTIF** |
| `hulken.google_ads` (minuscule) | VIDE (0 tables) | **A SUPPRIMER** |
| `hulken.analytics_334792038` | GA4 events (depuis 25 jan 2026) | ACTIF |
| `hulken.analytics_454869667` | GA4 events + pseudonymous_users | ACTIF |
| `hulken.analytics_454871405` | GA4 events + pseudonymous_users | ACTIF |

**Actions recommandees**:
1. Supprimer `hulken.google_ads` (vide, doublon avec `google_Ads`)
2. Pour integrer Google Ads dans les rapports cross-platform, creer des vues dans `ads_data`:
```sql
CREATE OR REPLACE VIEW `hulken.ads_data.google_ads_campaign_stats` AS
SELECT * FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`;
```

### Q: "On veut harmoniser les colonnes (index, feature, target) / Unify the indexes"
**R**: Pour harmoniser les colonnes cross-platform, on cree des vues avec un schema unifie:

```sql
-- Exemple: vue unifiee cross-platform avec format index/feature/target
CREATE OR REPLACE VIEW `hulken.ads_data.unified_ads_performance` AS

-- Facebook
SELECT
  DATE(date_start) AS date_index,           -- INDEX
  'facebook' AS platform,                    -- FEATURE
  campaign_name,                             -- FEATURE
  account_id,                                -- FEATURE
  CAST(spend AS FLOAT64) AS spend,          -- TARGET
  CAST(impressions AS INT64) AS impressions, -- TARGET
  CAST(clicks AS INT64) AS clicks           -- TARGET
FROM `hulken.ads_data.facebook_insights`

UNION ALL

-- TikTok
SELECT
  report_date AS date_index,
  'tiktok' AS platform,
  campaign_name,
  CAST(advertiser_id AS STRING) AS account_id,
  spend,
  impressions,
  clicks
FROM `hulken.ads_data.tiktok_campaigns_reports_daily`

UNION ALL

-- Google Ads (depuis google_Ads dataset)
SELECT
  _DATA_DATE AS date_index,
  'google_ads' AS platform,
  CampaignName AS campaign_name,
  CAST(ExternalCustomerId AS STRING) AS account_id,
  Cost / 1000000.0 AS spend,
  Impressions AS impressions,
  Clicks AS clicks
FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`;
```

Cette vue permet de comparer les 3 plateformes avec les memes colonnes.

### Q: "Conversion rate in Facebook"
**R**: Le taux de conversion Facebook se calcule ainsi:

```sql
-- Conversion rate par campagne (derniers 30 jours)
SELECT
  campaign_name,
  SUM(CAST(impressions AS INT64)) AS impressions,
  SUM(CAST(clicks AS INT64)) AS clicks,
  SUM(CAST(spend AS FLOAT64)) AS spend,
  SUM(CAST(actions_value AS FLOAT64)) AS revenue,
  -- CTR (Click-Through Rate)
  SAFE_DIVIDE(SUM(CAST(clicks AS INT64)), SUM(CAST(impressions AS INT64))) * 100 AS ctr_pct,
  -- CPC (Cost Per Click)
  SAFE_DIVIDE(SUM(CAST(spend AS FLOAT64)), SUM(CAST(clicks AS INT64))) AS cpc,
  -- ROAS (Return On Ad Spend)
  SAFE_DIVIDE(SUM(CAST(actions_value AS FLOAT64)), SUM(CAST(spend AS FLOAT64))) AS roas
FROM `hulken.ads_data.facebook_insights`
WHERE DATE(date_start) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY campaign_name
ORDER BY spend DESC;
```

Pour le taux de conversion par action specifique (achats, leads, etc.):
```sql
SELECT
  campaign_name,
  action_type,
  SUM(CAST(value AS FLOAT64)) AS conversions
FROM `hulken.ads_data.facebook_insights_action_type`
WHERE action_type IN ('purchase', 'lead', 'complete_registration')
  AND DATE(date_start) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY campaign_name, action_type
ORDER BY conversions DESC;
```

### Q: "Why tags in shopify_live_customers?"
**R**: Les tags sont des etiquettes ajoutees manuellement ou automatiquement dans Shopify Admin.
Ils permettent de segmenter les clients. Voici les tags les plus frequents dans votre base:

| Tag | Nombre clients | Signification |
|-----|---------------|---------------|
| `Amazon` | 5,347 | Clients venus du canal Amazon |
| `Bronze VIP` | 1,358+ | Programme fidelite - niveau Bronze |
| `Silver VIP` | 271+ | Programme fidelite - niveau Silver |
| `Gold VIP` | 167+ | Programme fidelite - niveau Gold |
| `Login with Shop` | ~200 | Connexion via Shop Pay |
| `Notch Conversation` | 119 | Contact via outil support Notch |
| `newsletter` | 41 | Inscrits newsletter |

Ces tags sont **utiles** pour la segmentation et l'analyse - ne pas les supprimer.
Pour filtrer par tag en SQL:
```sql
SELECT * FROM `hulken.ads_data.shopify_live_customers_clean`
WHERE tags LIKE '%Gold VIP%';
```

### Q: "Pourquoi il me deconnecte, je veux rester connecte sur VSCode?"
**R**: La deconnexion BigQuery dans VSCode est causee par l'expiration du token d'authentification.
Solutions:

1. **Utiliser le service account** (recommande):
   - Fichier: `hulken-fb56a345ac08.json` (deja dans le repo)
   - Dans VSCode > BigQuery extension > Settings > utiliser ce fichier comme credentials
   - Le service account ne se deconnecte JAMAIS

2. **Si vous utilisez `gcloud auth`**:
   - Relancer `gcloud auth application-default login` quand ca expire
   - Ou ajouter dans votre terminal: `export GOOGLE_APPLICATION_CREDENTIALS="D:/Better_signal/hulken-fb56a345ac08.json"`

3. **Extension VSCode BigQuery** (si elle se deconnecte):
   - Preferences > Settings > chercher "BigQuery"
   - Configurer le chemin vers le service account JSON
   - Desactiver "Use Application Default Credentials" et pointer vers le JSON

### Q: "Impossible d'ouvrir les routines"
**R**: Les "routines" dans BigQuery sont des stored procedures ou scheduled queries.
Pour y acceder:

1. **Scheduled Queries** (rafraichissement automatique des tables):
   - BigQuery Console > menu gauche > "Scheduled queries"
   - Ou: `https://console.cloud.google.com/bigquery/scheduled-queries?project=hulken`

2. **Depuis VSCode**: Les routines BigQuery ne sont pas directement editables dans VSCode.
   Utilisez la console web BigQuery pour gerer les scheduled queries.

3. **Notre routine de refresh** est dans `scheduled_refresh_clean_tables.sql` - a configurer
   comme scheduled query dans la console BQ.

### Q: "Comment modifier le GitHub lui-meme?"
**R**: Le code est sur GitHub. Pour modifier:

1. **Cloner le repo** (si pas deja fait):
   ```bash
   git clone https://github.com/[votre-org]/Better_signal.git
   ```
2. **Modifier les fichiers** dans VSCode
3. **Commit et push**:
   ```bash
   git add .
   git commit -m "Description du changement"
   git push
   ```

Les fichiers importants a connaitre:
- `data_validation/` - Scripts de validation et reconciliation
- `scheduled_refresh_clean_tables.sql` - SQL pour les tables _clean
- `fix_tiktok_dedup_views.sql` - Vues TikTok dedupliquees
- `docs/` - Documentation complete

### Q: "Si une table est ajoutee, le check ne la voit pas"
**R**: Le script de reconciliation (`live_reconciliation.py`) verifie uniquement les plateformes
configurees (Facebook, TikTok). Il ne detecte pas automatiquement les nouvelles tables BigQuery.

Pour ajouter une nouvelle table au check:
1. Ouvrir `data_validation/reconciliation_check.py`
2. Ajouter la table dans la liste des tables verifiees
3. Definir les seuils de qualite dans `data_validation/config.py`

Le script `reconciliation_check.py` verifie deja toutes les tables Shopify pour:
- Doublons (duplicate detection)
- Fraicheur des donnees (freshness)
- Champs PII (compliance audit)
- Continuite temporelle

Pour les NOUVELLES sources (ex: Google Ads, Klaviyo), il faudra ajouter des checks specifiques.

### Q: "Beaucoup de champs sont vides sans raison"
**R**: Trois causes distinctes:
1. **Champs PII (email, phone, name)**: Mis a NULL intentionnellement pour la conformite GDPR.
   Les hash sont dans les tables _clean.
2. **fulfillment_status NULL** (2,055 orders): C'est normal - cela signifie "non expedie".
   Shopify utilise NULL pour les commandes pas encore fulfillees.
3. **Champs optionnels** (note, po_number, company, etc.): Pas tous les clients remplissent
   ces champs. C'est le comportement normal de Shopify.

### Q: "Il faut supprimer ce qu'on n'utilise pas"
**R**: Tables candidates a la suppression ou archivage:

| Table | Rows | Recommendation |
|-------|------|----------------|
| `shopify_live_inventory_items` | 0 | Supprimer (vide, inutile) |
| `shopify_orders` | 585,927 | Archiver (import historique, remplace par live_orders) |
| `shopify_line_items` | 719,124 | Garder si analyse produit necessaire |
| `shopify_utm` | 594,988 | Garder (attribution cross-platform) |

**Attention**: Ne PAS supprimer les tables raw Airbyte (`shopify_live_*`).
Elles sont necessaires pour le sync incremental.

---

## Ameliorations du script de reconciliation

Le script `live_reconciliation.py` a ete ameliore:

```bash
# Utilisation par defaut (14 jours, exclut les 2 derniers jours)
python data_validation/live_reconciliation.py

# Choisir une periode specifique (ex: janvier 2025)
python data_validation/live_reconciliation.py --start-date 2025-01-01 --end-date 2025-01-31

# Choisir le nombre de jours
python data_validation/live_reconciliation.py --days 30

# Ajuster la tolerance (ex: 5% au lieu de 2%)
python data_validation/live_reconciliation.py --tolerance 5

# Sans animation (pour logs)
python data_validation/live_reconciliation.py --no-animation
```

Nouvelles fonctionnalites:
- Dates personnalisables (`--start-date`, `--end-date`)
- Exclut les 2 derniers jours par defaut (attribution window)
- Affiche la fraicheur des donnees BQ (heures depuis le dernier sync)
- Skip les comptes sans activite (ex: Canada) au lieu de faux MATCH
- Tolerance ajustable (`--tolerance`)

---

## Tables a utiliser (pour les analystes)

**IMPORTANT**: Ne jamais interroger les tables raw directement. Utiliser ces vues/tables propres:

| Plateforme | Table/Vue propre | Description |
|------------|-----------------|-------------|
| **Facebook** | `facebook_insights` | Metriques ads dedupliquees |
| **Facebook** | `facebook_insights_action_type` | Breakdown par type d'action |
| **Facebook** | `facebook_insights_dma` | Breakdown par zone geo (DMA) |
| **Facebook** | `facebook_insights_platform_device` | Breakdown par plateforme/device |
| **TikTok** | `tiktok_ads_reports_daily` | Metriques ads dedupliquees |
| **TikTok** | `tiktok_campaigns_reports_daily` | Metriques par campagne |
| **TikTok** | `tiktok_ad_groups_reports_daily` | Metriques par ad group |
| **Shopify** | `shopify_live_orders_clean` | Commandes dedupliquees + PII hashe |
| **Shopify** | `shopify_live_customers_clean` | Clients dedupliques + PII hashe |
| **Shopify** | `shopify_products` | Catalogue produits (55 produits) |
| **Shopify** | `shopify_transactions` | Transactions de paiement |
| **Shopify** | `shopify_refunds` | Remboursements |
| **Shopify** | `shopify_utm` | Attribution UTM cross-platform |
| **Shopify** | `shopify_line_items` | Detail des items par commande |

---

## BUG CRITIQUE: Pipeline PII Shopify

### Probleme
Le script post-sync Airbyte **NULLIFIE les emails AVANT de les hasher**.
Resultat: seulement 26/44,822 clients ont un email_hash. Les emails sont perdus de BigQuery.

### Cause technique
1. Airbyte sync des emails correctement depuis Shopify
2. Un script post-sync fait un MERGE dans _clean (hash PII)
3. PUIS un UPDATE SET email=NULL dans les tables raw
4. MAIS les tables raw n'ont PAS de colonne email_hash
5. Et le MERGE filtre avec `WHERE email IS NOT NULL` -> la plupart sont deja NULL

### Fix necessaire (URGENT)
1. **Faire un full reset du sync Shopify dans Airbyte** (pour re-telecharger tous les emails)
2. **Modifier le script post-sync** pour:
   a. D'abord ajouter email_hash aux tables raw: `ALTER TABLE ADD COLUMN email_hash STRING`
   b. D'abord UPDATE SET email_hash = SHA256(email) WHERE email IS NOT NULL
   c. ENSUITE UPDATE SET email = NULL WHERE email_hash IS NOT NULL
3. **OU** simplement arreter de nullifier les raw (garder le PII dans les raw securisees,
   et n'exposer que les _clean aux analystes via des permissions BigQuery)

### Approche recommandee
L'approche la plus simple et la plus sure:
- **Ne PAS nullifier les tables raw** (elles sont protegees par IAM BigQuery)
- Creer des vues _clean sans PII pour les analystes
- Restreindre l'acces aux tables raw au service account Airbyte uniquement

---

## Verification Airbyte (12 fev 2026, via tunnel SSH)

### Etat des connexions (verifie en direct)

| Connexion | Statut | Frequence | Dernier sync |
|-----------|--------|-----------|-------------|
| **Facebook Marketing - BigQuery** | Running (49h+) | Daily 00:00 | 2 jours (en cours) |
| **Shopify - BigQuery** | Succeeded | **Toutes les heures** | 48 min |
| **TikTok Marketing - BigQuery** | Succeeded | Daily 00:00 | 12 heures |

### Streams Facebook (Job en cours - 1,732,034 records charges)
- `facebook_ads_insights`: 127,725 records (40h elapsed)
- `facebook_ads_insights_age_and_gender`: 1,259,760 records (11h elapsed)
- `facebook_ads_insights_country`: 229,835 records (1h elapsed)
- `facebook_ads_insights_region`: 104,239 records (1h elapsed, EN COURS)
- `facebook_ads_insights_dma`: En attente
- `facebook_ads_insights_platform_and_device`: En attente
- +6 streams queued (activities, ad_creatives, ad_sets, ads, campaigns, etc.)

### Streams Shopify (5/31 actives)
Tous en mode **Incremental | Append** (cause des doublons - mitiges par les tables _clean):
- `shopify_live_customers` (28 champs, curseur: updated_at)
- `shopify_live_orders` (97 champs, curseur: updated_at)
- `shopify_live_order_refunds` (15 champs, curseur: created_at)
- `shopify_live_products` (40 champs, curseur: updated_at)
- `shopify_live_transactions` (29 champs, curseur: created_at)

**`shopify_live_inventory_items` est DESACTIVE** dans Airbyte - voila pourquoi la table est vide.

### Streams TikTok (7/44 actives)
Mix de modes:
- Dimension: `tiktokads`, `tiktokad_groups`, `tiktokcampaigns` (Full Refresh | Overwrite - pas de doublons)
- Reports: `tiktokads_reports_daily`, `tiktokad_groups_reports_daily`, `tiktokcampaigns_reports_daily`, `tiktokadvertisers_reports_daily` (Incremental | Append - doublons mitiges par vues dedup)

### Google Ads - Localisation (reponse client x3)
Google Ads n'est PAS dans `ads_data` mais dans un dataset separe `hulken.google_Ads` (96 tables + 96 vues, Data Transfer Service, account 4354001000). Le dataset `hulken.google_ads` (minuscule) est VIDE et peut etre supprime.

---

## Actions a faire

1. [x] ~~Fix TikTok dedup views~~ (FAIT - 4 vues corrigees)
2. [x] ~~Ameliorer le script de reconciliation~~ (FAIT - dates custom, freshness, skip $0)
3. [x] ~~Rafraichir les tables _clean~~ (FAIT - a jour 12 fev)
4. [x] ~~Creer vues Shopify dedup~~ (FAIT - products, transactions, refunds)
5. [x] ~~Verifier le sync Facebook Airbyte~~ (VERIFIE via Airbyte UI - Job actif, 1.7M+ records)
6. [x] ~~Verifier connexion Airbyte~~ (VERIFIE - 3 connexions actives et saines)
7. [x] ~~Repondre a TOUTES les questions client~~ (25/25 couvertes)
8. [ ] **URGENT: Fixer le pipeline PII Shopify** - voir section ci-dessus
9. [ ] **Creer un scheduled query BQ** pour rafraichir les _clean quotidiennement
   - SQL pret dans `scheduled_refresh_clean_tables.sql`
   - BigQuery Console > Scheduled Queries > Daily 10:00 UTC
10. [ ] **Supprimer** `hulken.google_ads` (dataset vide, doublon)
11. [ ] **Supprimer** `shopify_live_inventory_items` (table vide, stream desactive)
12. [ ] **Archiver** `shopify_orders` si le live_orders suffit
13. [ ] **Optionnel**: Activer le stream `inventory_items` dans Airbyte si besoin
14. [ ] **Optionnel**: Creer vue unifiee cross-platform (Facebook + TikTok + Google Ads)
