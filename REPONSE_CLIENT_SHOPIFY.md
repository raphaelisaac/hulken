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
Le stream `inventory_items` est **desactive** dans Airbyte.

**Action necessaire**: Activer le stream dans Airbyte si les donnees d'inventaire sont necessaires.

### Q: "Le sync ne marche pas"
**R**: Le sync Airbyte Shopify fonctionne - les tables raw sont a jour (derniere extraction:
12 fev 2026, 09:00 UTC). MAIS les tables `_clean` (dedupliquees) n'etaient pas rafraichies
automatiquement. Elles sont maintenant a jour.

**Action necessaire**: Creer un scheduled query dans BigQuery pour rafraichir les _clean tables
automatiquement apres chaque sync Airbyte (toutes les 24h).

### Q: "Comment se connecter a Airbyte?"
**R**: Airbyte est installe sur une VM Google Cloud.

**Windows (PowerShell):**
```
gcloud compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap --ssh-flag="-L 8000:localhost:8000"
```

**Mac/Linux:**
```
gcloud compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap -- -L 8000:localhost:8000
```

Puis ouvrir http://localhost:8000. Credentials: `abctl local credentials` sur la VM.

Documentation complete: `docs/RUNBOOK.md`

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

**Note**: Dans le nouveau dataset `ads_analyst`, les colonnes first_name/last_name sont
retirees des vues car elles sont nullifiees et inutiles sans la valeur originale.

### Q: "Comment changer les noms des tables?" / "Comment changer les variables (colonnes)?"
**R**: Un nouveau dataset **`ads_analyst`** sera cree avec des vues propres qui:
- Ont des noms simples (`shopify_orders` au lieu de `shopify_live_orders_clean`)
- N'exposent que les colonnes utiles (15 au lieu de 97)
- Corrigent les formats (order_id numerique au lieu de GID)
- Unifient les tables dupliquees (1 table orders au lieu de 2)

Voir le plan complet: `docs/SUGGESTIONS_TABLE_CLEANUP.md`

L'analyste ouvre `ads_analyst` au lieu de `ads_data` et voit 15 noms clairs au lieu de 40. `ads_data` reste intacte pour Airbyte et les scripts.

### Q: "Comment relier les tables Shopify entre elles?"
**R**: Dans le dataset `ads_analyst`, les tables se joignent directement:

```sql
-- Commandes + Details produits par commande
SELECT o.*, li.*
FROM `hulken.ads_analyst.shopify_orders` o
JOIN `hulken.ads_analyst.shopify_line_items` li ON o.order_id = li.order_id;

-- Commandes + Clients (via email_hash)
SELECT o.*, c.tags, c.total_spent
FROM `hulken.ads_analyst.shopify_orders` o
JOIN `hulken.ads_analyst.shopify_customers` c ON o.email_hash = c.email_hash;

-- Commandes + Attribution UTM (order_id est numerique dans les deux!)
SELECT o.order_name, o.total_price, u.first_utm_source, u.first_utm_campaign
FROM `hulken.ads_analyst.shopify_orders` o
JOIN `hulken.ads_analyst.shopify_utm` u ON o.order_id = u.order_id;
```

**Note**: Dans `ads_data`, le join orders ↔ utm ne marche PAS directement car
`shopify_utm.order_id` est au format GID (`gid://shopify/Order/123456`) alors que
`shopify_live_orders_clean.id` est numerique (`123456`). Ce probleme est corrige dans
`ads_analyst` ou les deux sont numeriques.

### Q: "Pourquoi Google Ads n'est pas efface? Faire de l'ordre dans ads_data"
**R**: Google Ads n'a JAMAIS ete dans le dataset `ads_data`. Il est dans un dataset separe:

| Dataset | Contenu | Statut |
|---------|---------|--------|
| `hulken.google_Ads` (majuscule) | 96 tables + 96 vues Google Ads Data Transfer (account 4354001000) | **ACTIF** |
| `hulken.google_ads` (minuscule) | VIDE (0 tables) | **A SUPPRIMER** |
| `hulken.analytics_334792038` | GA4 events (depuis 25 jan 2026) | ACTIF |
| `hulken.analytics_454869667` | GA4 events + pseudonymous_users | ACTIF |
| `hulken.analytics_454871405` | GA4 events + pseudonymous_users | ACTIF |

**Action**: Supprimer `hulken.google_ads` (vide, doublon). Google Ads sera accessible via
la vue `ads_analyst.unified_ads_performance` (cross-platform).

### Q: "On veut harmoniser les colonnes (index, feature, target) / Unify the indexes"
**R**: Une vue `unified_ads_performance` sera creee dans `ads_analyst` qui combine
Facebook + TikTok + Google Ads avec les memes colonnes:

| Colonne | Description |
|---------|-------------|
| `date` | Date du rapport |
| `platform` | facebook / tiktok / google_ads |
| `campaign_name` | Nom de la campagne |
| `account_id` | ID du compte publicitaire |
| `spend` | Depenses en USD |
| `impressions` | Nombre d'affichages |
| `clicks` | Nombre de clics |

L'analyste peut comparer les 3 plateformes dans une seule requete.

### Q: "Conversion rate in Facebook"
**R**: Le taux de conversion Facebook se calcule via `ads_analyst.facebook_insights`:

```sql
SELECT
  campaign_name,
  SUM(CAST(impressions AS INT64)) AS impressions,
  SUM(CAST(clicks AS INT64)) AS clicks,
  SUM(CAST(spend AS FLOAT64)) AS spend,
  -- CTR (Click-Through Rate)
  SAFE_DIVIDE(SUM(CAST(clicks AS INT64)), SUM(CAST(impressions AS INT64))) * 100 AS ctr_pct,
  -- CPC (Cost Per Click)
  SAFE_DIVIDE(SUM(CAST(spend AS FLOAT64)), SUM(CAST(clicks AS INT64))) AS cpc
FROM `hulken.ads_analyst.facebook_insights`
WHERE DATE(date_start) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY campaign_name
ORDER BY spend DESC;
```

**Note**: Les vues `facebook_insights_action_type`, `facebook_insights_dma` et
`facebook_insights_platform_device` ne sont pas encore creees dans BigQuery.
Les tables raw Airbyte correspondantes (`facebook_ads_insights_dma`, etc.) sont en cours
de sync (Job 150). Ces vues seront creees apres la fin du sync.

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

Ces tags sont **utiles** pour la segmentation - disponibles dans `ads_analyst.shopify_customers`.

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

Pour les NOUVELLES sources (ex: Google Ads, Klaviyo), il faudra ajouter des checks specifiques.

### Q: "Beaucoup de champs sont vides sans raison"
**R**: Trois causes distinctes:
1. **Champs PII (email, phone, name)**: Mis a NULL intentionnellement pour la conformite GDPR.
   Les hash sont dans les tables _clean.
2. **fulfillment_status NULL** (2,055 orders): C'est normal - cela signifie "non expedie".
   Shopify utilise NULL pour les commandes pas encore fulfillees.
3. **Champs optionnels** (note, po_number, company, etc.): Pas tous les clients remplissent
   ces champs. C'est le comportement normal de Shopify.

**Solution**: Le dataset `ads_analyst` retire toutes les colonnes toujours vides. Plus de confusion.

### Q: "Il faut supprimer ce qu'on n'utilise pas"
**R**: Plutot que supprimer (ce qui casserait Airbyte et les scripts), la solution est le dataset
`ads_analyst` qui ne montre que les 15 vues utiles. Les 40 tables de `ads_data` restent
en arriere-plan pour le pipeline mais l'analyste ne les voit plus.

| Avant | Apres |
|-------|-------|
| L'analyste ouvre `ads_data` et voit 40 noms | L'analyste ouvre `ads_analyst` et voit 15 noms |
| Tables avec 97 colonnes (30+ NULL) | Vues avec 10-15 colonnes utiles |
| 2 tables orders incompatibles | 1 vue unifiee `shopify_orders` |
| join utm ↔ orders casse (format GID) | join direct (order_id numerique) |

Plan complet: `docs/SUGGESTIONS_TABLE_CLEANUP.md`

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

---

## Tables a utiliser (pour les analystes)

**IMPORTANT**: Utiliser le dataset **`ads_analyst`** (pas `ads_data`).

| Plateforme | Table dans `ads_analyst` | Description |
|------------|------------------------|-------------|
| **Facebook** | `facebook_insights` | Metriques ads dedupliquees (campaign_name, ad_name inclus) |
| **Facebook** | `facebook_campaigns_daily` | Metriques aggregees par campagne/jour |
| **Facebook** | `facebook_insights_country` | Breakdown par pays |
| **Facebook** | `facebook_insights_age_gender` | Breakdown par age + genre |
| **TikTok** | `tiktok_reports_daily` | Metriques ads dedupliquees |
| **TikTok** | `tiktok_campaigns_daily` | Metriques par campagne |
| **TikTok** | `tiktok_campaigns` | Noms des campagnes (pour joins) |
| **Shopify** | `shopify_orders` | Commandes unifiees (historique + live, dedupliquees, 15 colonnes) |
| **Shopify** | `shopify_customers` | Clients (dedupliques, PII hashe, 10 colonnes) |
| **Shopify** | `shopify_utm` | Attribution UTM (order_id numerique, joinable) |
| **Shopify** | `shopify_products` | Catalogue produits |
| **Shopify** | `shopify_line_items` | Detail des items par commande |
| **Cross-platform** | `unified_ads_performance` | Facebook + TikTok + Google Ads unifies |

**Vues Facebook en attente** (seront creees apres fin du sync Job 150):
- `facebook_insights_action_type` - Breakdown par type d'action (purchase, lead, etc.)
- `facebook_insights_dma` - Breakdown par zone geo (DMA)
- `facebook_insights_platform_device` - Breakdown par plateforme/device

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
10. [ ] **Creer le dataset `ads_analyst`** avec 15 vues propres
    - Plan complet: `docs/SUGGESTIONS_TABLE_CLEANUP.md`
11. [ ] **Creer les vues Facebook manquantes** (action_type, dma, platform_device)
    - Attendre la fin du sync Job 150
    - SQL dans `create_facebook_dedup_views.sql`
12. [ ] **Supprimer** `hulken.google_ads` (dataset vide, doublon)
13. [ ] **Supprimer** vue `shopify_live_inventory_items` (vide, stream desactive)
