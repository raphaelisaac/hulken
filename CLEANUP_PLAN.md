# Plan de nettoyage - data_validation/

**Date:** 2026-02-13

---

## Fichiers actuels analysés

| Fichier | Taille | Ce qu'il fait | Action |
|---------|--------|---------------|--------|
| **live_reconciliation.py** | 28K | ✅ Compare API vs BigQuery (Shopify, Facebook, TikTok) | **GARDER + AMÉLIORER** |
| reconciliation_check.py | 46K | Vérifications qualité (freshness, PII, duplicates) | Fusionner dans live |
| reconciliation_app.py | 15K | Dashboard Streamlit pour SOC checks | Fusionner dans live |
| reconciliation_report.py | 17K | Génération rapports HTML | Archiver (pas utilisé) |
| soc_checks.py | 22K | SOC compliance checks | Garder (utilisé par app) |
| sync_watchdog.py | 8.8K | Surveillance syncs Airbyte (cron) | Fusionner dans live |
| **table_monitoring.py** | 12K | ✅ Détection tables vides/nouvelles | **GARDER** (nouveau) |
| validate_data.py | 14K | Validation des données | Fusionner dans live |
| anonymize_pii.py | 13K | Anonymisation PII | **GARDER** (unique) |
| config.py | 4.6K | Configuration | **GARDER** |
| run_*.bat | - | Scripts Windows | Supprimer (sur Mac) |

---

## NOUVEAU: Super live_reconciliation.py

### Fonctionnalités combinées

```
SUPER live_reconciliation.py
│
├── 1. VALIDATION API vs BigQuery (déjà fait)
│   ├── Shopify (orders, revenue)
│   ├── Facebook (spend, impressions, clicks)
│   └── TikTok (spend, impressions, clicks)
│
├── 2. DÉTECTION NOUVELLES TABLES (de table_monitoring.py)
│   ├── Tables vides
│   ├── Tables nouvelles dans Airbyte
│   └── Tables non synchronisées 48h+
│
├── 3. VÉRIFICATION QUALITÉ DONNÉES (de reconciliation_check.py)
│   ├── Freshness (dernière sync)
│   ├── PII compliance (hash vs clair)
│   ├── Duplicates (dans tables raw vs clean)
│   └── Missing data (NULL counts)
│
├── 4. SURVEILLANCE SYNCS AIRBYTE (de sync_watchdog.py)
│   ├── État des connections
│   ├── Dernière exécution
│   └── Erreurs récentes
│
└── 5. DASHBOARD STREAMLIT OPTIONNEL (de reconciliation_app.py)
    ├── Mode interactif: streamlit run live_reconciliation.py
    └── Mode CLI: python live_reconciliation.py
```

### Arguments CLI

```bash
# Mode normal (API vs BigQuery + détection tables)
python live_reconciliation.py

# Mode complet (TOUT)
python live_reconciliation.py --full

# Seulement détection nouvelles tables
python live_reconciliation.py --check-tables

# Seulement qualité des données
python live_reconciliation.py --check-quality

# Dashboard Streamlit
streamlit run live_reconciliation.py
```

---

## Actions à prendre

### GARDER (essentiels)

- ✅ `live_reconciliation.py` (à améliorer)
- ✅ `table_monitoring.py` (nouveau, utile)
- ✅ `anonymize_pii.py` (unique, PII management)
- ✅ `config.py` (configuration)
- ✅ `soc_checks.py` (si SOC compliance nécessaire)

### ARCHIVER (redondants)

- 📦 `reconciliation_check.py` → Fonctionnalités fusionnées dans live
- 📦 `reconciliation_app.py` → Dashboard fusionné dans live
- 📦 `reconciliation_report.py` → Pas utilisé
- 📦 `validate_data.py` → Fusionné dans live
- 📦 `sync_watchdog.py` → Fusionné dans live

### SUPPRIMER (inutiles)

- ❌ `run_real_reconciliation.bat` (Windows, vous êtes sur Mac)
- ❌ `run_reconciliation.bat` (Windows)
- ❌ `reconciliation_results.json` (généré, pas versionné)

---

## Structure finale

```
data_validation/
├── live_reconciliation.py      ⭐ SUPER SCRIPT (tout en un)
├── table_monitoring.py          ✅ Détection tables (standalone)
├── anonymize_pii.py             ✅ Gestion PII
├── config.py                    ✅ Configuration
├── soc_checks.py                ✅ SOC compliance (optionnel)
├── .env                         🔑 Credentials
├── .env.template                📝 Template
│
└── archive_old_scripts/         📦 Anciens scripts
    ├── reconciliation_check.py
    ├── reconciliation_app.py
    ├── reconciliation_report.py
    ├── validate_data.py
    └── sync_watchdog.py
```

---

## Prochaines étapes

1. ✅ Créer le super live_reconciliation.py
2. ⏳ Tester avec: `python live_reconciliation.py --full`
3. ⏳ Archiver les anciens scripts
4. ⏳ Supprimer les fichiers Windows
5. ⏳ Mettre à jour COMPLETE_GUIDE.md

