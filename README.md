# Hulken / Better Signal - Configuration & Scripts

**Dernière mise à jour:** 2026-02-13
**Projet BigQuery:** hulken
**Dataset principal:** ads_data

---

## Structure du projet

```
vscode_config/
├── README.md                    # Ce fichier
├── DOCUMENTATION_INDEX.md       # Index de la documentation
│
├── sql/                         # Scripts SQL BigQuery
│   ├── EXPORT_TIKTOK_DATA.sql
│   ├── create_facebook_dedup_views.sql
│   ├── fix_tiktok_dedup_views.sql
│   └── scheduled_refresh_clean_tables.sql
│
├── data_validation/             # Scripts de validation des données
│   ├── live_reconciliation.py   # ⭐ Validation API vs BigQuery (client demo)
│   ├── reconciliation_app.py
│   ├── reconciliation_check.py
│   ├── reconciliation_report.py
│   └── anonymize_pii.py
│
├── pii/                         # Scripts de gestion PII (hashing, anonymisation)
│   ├── hash_all_emails.sql
│   ├── nullify_pii_after_hash.sql
│   ├── verify_hash_consistency.sql
│   └── restore_emails_from_backup.py
│
├── docs/                        # Documentation complète
│   ├── RUNBOOK.md              # Guide opérationnel
│   ├── DATA_REFERENCE.md       # Référence des tables
│   ├── QUERY_LIBRARY.md        # Bibliothèque de requêtes SQL
│   ├── TROUBLESHOOTING.md      # Dépannage
│   └── client-reports/         # Rapports clients
│
├── tasks/                       # Tâches en cours et complétées
│
├── vm_scripts/                  # Scripts pour la VM GCP
│
├── archive/                     # Fichiers archivés (obsolètes mais conservés)
│   ├── analyseavant.txt
│   ├── oporblemeclien.txt
│   └── REPONSE_CLIENT_SHOPIFY.md
│
├── data_explorer.py             # 🔧 Dashboard Streamlit pour explorer BigQuery
├── get_refresh_token.py         # Utilitaire OAuth
├── setup_vscode_mac.sh          # Script de setup pour Mac
└── vm_command.py                # Commandes VM
```

---

## Outils principaux

### 1. **Data Explorer** (`data_explorer.py`)
Dashboard Streamlit interactif pour explorer les données BigQuery.

```bash
streamlit run data_explorer.py
```

**Fonctionnalités:**
- Exploration de toutes les tables BigQuery
- Prévisualisation des données
- Export CSV
- Requêtes SQL personnalisées
- Requêtes rapides prédéfinies

---

### 2. **Live Reconciliation** (`data_validation/live_reconciliation.py`)
Script de validation en temps réel comparant les API sources (Shopify, Facebook, TikTok) avec BigQuery.

```bash
# Validation complète (toutes les plateformes)
python data_validation/live_reconciliation.py

# Derniers 30 jours
python data_validation/live_reconciliation.py --days 30

# Période personnalisée
python data_validation/live_reconciliation.py --start-date 2025-01-01 --end-date 2025-01-31

# Une seule plateforme
python data_validation/live_reconciliation.py --platform shopify

# Sans animation (pour logs)
python data_validation/live_reconciliation.py --no-animation

# Tolérance personnalisée (défaut: 2%)
python data_validation/live_reconciliation.py --tolerance 5
```

**Ce qu'il vérifie:**
- **Shopify:** Nombre de commandes, revenu total
- **Facebook Ads:** Dépenses, impressions, clics
- **TikTok Ads:** Dépenses, impressions, clics

**Résultat:** Comparaison visuelle avec indicateurs MATCH/MISMATCH

---

## Scripts SQL importants

### [scheduled_refresh_clean_tables.sql](sql/scheduled_refresh_clean_tables.sql)
Rafraîchissement quotidien des tables Shopify nettoyées (dédupliquées + PII hashé).

**Planification BigQuery:** Tous les jours à 10:00 UTC

**Tables concernées:**
- `shopify_live_orders_clean`
- `shopify_live_customers_clean`

---

### [EXPORT_TIKTOK_DATA.sql](sql/EXPORT_TIKTOK_DATA.sql)
Export complet des données TikTok Ads pour analyse externe.

---

### [create_facebook_dedup_views.sql](sql/create_facebook_dedup_views.sql)
Création de vues dédupliquées pour Facebook Ads.

---

## Connexion à BigQuery

### Prérequis
1. **Credentials:** Fichier JSON de service account dans `data_validation/`
2. **Variables d'environnement:** Fichier `.env` dans `data_validation/`

```bash
# .env
GOOGLE_APPLICATION_CREDENTIALS=/path/to/hulken-credentials.json
BIGQUERY_PROJECT=hulken
BIGQUERY_DATASET=ads_data

# API Credentials (pour live_reconciliation)
SHOPIFY_STORE=your-store
SHOPIFY_ACCESS_TOKEN=shpat_xxx
FACEBOOK_ACCESS_TOKEN=xxx
FACEBOOK_ACCOUNT_IDS=123456789,987654321
TIKTOK_ACCESS_TOKEN=xxx
TIKTOK_ADVERTISER_ID=xxx
```

### Connexion via Python

```python
from google.cloud import bigquery
import os

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = 'hulken-credentials.json'
client = bigquery.Client(project='hulken')

# Exemple de requête
query = """
SELECT DATE(created_at) AS date,
       COUNT(*) AS orders,
       SUM(total_price) AS revenue
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC
"""

df = client.query(query).to_dataframe()
print(df)
```

---

## Datasets BigQuery

| Dataset | Description | Tables principales |
|---------|-------------|-------------------|
| `ads_data` | Données marketing et e-commerce | `shopify_live_orders_clean`, `facebook_insights`, `tiktok_ads_reports_daily`, `shopify_utm` |
| `google_Ads` | Google Ads | `ads_CampaignBasicStats_*` |
| `analytics_334792038` | Google Analytics 4 (EU) | GA4 tables |
| `analytics_454869667` | Google Analytics 4 (US) | GA4 tables |
| `analytics_454871405` | Google Analytics 4 (CA) | GA4 tables |

---

## Tables principales (ads_data)

### Shopify
- `shopify_live_orders` - Commandes brutes (avec PII)
- `shopify_live_orders_clean` - ⭐ Commandes dédupliquées, PII hashé
- `shopify_live_customers_clean` - Clients dédupliqués, PII hashé
- `shopify_utm` - Attribution UTM des commandes

### Facebook Ads
- `facebook_insights` - Métriques publicitaires dédupliquées
- `facebook_ads_insights` - Table brute Airbyte

### TikTok Ads
- `tiktok_ads_reports_daily` - Rapports quotidiens dédupliqués
- `tiktokads_reports_daily` - Table brute Airbyte

---

## Gestion PII (Informations personnelles)

Les données personnelles (emails, téléphones, adresses) sont:
1. **Hashées** avec SHA256 lors du rafraîchissement des tables `_clean`
2. **Nullifiées** dans les tables brutes après hashing pour conformité RGPD

**Scripts PII:**
- [hash_all_emails.sql](pii/hash_all_emails.sql) - Hashage initial
- [nullify_pii_after_hash.sql](pii/nullify_pii_after_hash.sql) - Suppression PII
- [verify_hash_consistency.sql](pii/verify_hash_consistency.sql) - Vérification intégrité

---

## Documentation complète

Voir [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) pour l'index complet de la documentation.

**Guides principaux:**
- [docs/RUNBOOK.md](docs/RUNBOOK.md) - Guide opérationnel complet
- [docs/DATA_REFERENCE.md](docs/DATA_REFERENCE.md) - Référence des tables et colonnes
- [docs/QUERY_LIBRARY.md](docs/QUERY_LIBRARY.md) - Bibliothèque de requêtes SQL
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Résolution de problèmes

---

## Nettoyage effectué (2026-02-13)

**Actions:**
- ✅ Création dossier `sql/` pour tous les scripts SQL
- ✅ Création dossier `archive/` pour fichiers obsolètes
- ✅ Suppression des scripts Windows (.bat) inutiles sur Mac
- ✅ Déplacement des fichiers temporaires vers `archive/`

**Résultat:** Structure plus claire et organisée, fichiers faciles à trouver

---

## Support

Pour toute question ou problème:
1. Consulter [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Vérifier [docs/RUNBOOK.md](docs/RUNBOOK.md)
3. Utiliser `data_explorer.py` pour explorer les données

---

*Dernière mise à jour: 2026-02-13*
