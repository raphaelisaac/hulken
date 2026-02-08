# Documentation Index - Hulken/Better Signals

**Dernière mise à jour:** 2026-02-04
**Projet BigQuery:** hulken
**Dataset:** ads_data

---

## Structure Simplifiée

```
D:\Better_signal\
├── DOCUMENTATION_INDEX.md      # Cet index
│
├── docs/                       # DOCUMENTATION (6 fichiers)
│   ├── RUNBOOK.md             # Guide opérationnel unifié
│   ├── DATA_REFERENCE.md      # Référence tables & colonnes
│   ├── QUERY_LIBRARY.md       # Bibliothèque SQL
│   ├── TROUBLESHOOTING.md     # Résolution problèmes
│   ├── EXPORT_IMPORT_GUIDE.md # Workflows ETL
│   └── client-reports/        # Rapports client (3)
│
├── tasks/                      # Tâches en cours (6)
├── archive/                    # Documents archivés (25+)
├── data_validation/            # Scripts Python
├── pii/                        # Scripts PII
└── Shopify/                    # Données JSONL
```

---

## Documentation Principale (`docs/`)

| Document | Description | Usage |
|----------|-------------|-------|
| [RUNBOOK.md](docs/RUNBOOK.md) | **Guide opérationnel unifié** - Airbyte, BigQuery, Looker, PM2 | Ops, Analysts |
| [DATA_REFERENCE.md](docs/DATA_REFERENCE.md) | **Référence complète** - Tables, colonnes, PII, liaisons | Technique |
| [QUERY_LIBRARY.md](docs/QUERY_LIBRARY.md) | **Bibliothèque SQL** - Revenue, ROAS, LTV, diagnostics | Analysts |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | **Résolution problèmes** - Auth, queries, data issues | Support |
| [EXPORT_IMPORT_GUIDE.md](docs/EXPORT_IMPORT_GUIDE.md) | **Workflows ETL** - Export, cleaning, import | Data Eng |

---

## Rapports Client (`docs/client-reports/`)

| Rapport | Description |
|---------|-------------|
| [CLIENT_DATA_INFRASTRUCTURE_REPORT.md](docs/client-reports/CLIENT_DATA_INFRASTRUCTURE_REPORT.md) | Infrastructure complète (87 tables, 8M+ records) |
| [HULKEN_TIKTOK_REPORT_CLIENT.md](docs/client-reports/HULKEN_TIKTOK_REPORT_CLIENT.md) | Analyse TikTok ($970K spend, 3.5 ans) |
| [FACEBOOK_ADS_DEEP_ANALYSIS.md](docs/client-reports/FACEBOOK_ADS_DEEP_ANALYSIS.md) | Analyse Facebook Europe ($331K) |

---

## Accès Rapide

| Besoin | Document |
|--------|----------|
| Accéder à Airbyte | `docs/RUNBOOK.md` → Section 2 |
| Setup VSCode/BigQuery | `docs/RUNBOOK.md` → Section 3 |
| Liste des tables | `docs/DATA_REFERENCE.md` → Section 2-4 |
| Requêtes ROAS | `docs/QUERY_LIBRARY.md` → Section 2-3 |
| Problème connexion | `docs/TROUBLESHOOTING.md` |
| Exporter données | `docs/EXPORT_IMPORT_GUIDE.md` |

---

## Tâches (`tasks/`)

| Fichier | Statut |
|---------|--------|
| TASK_02_PII_RESTORATION_HASH.md | ⏳ En cours |
| TASK_04_UTM_CRON_VERIFICATION.md | ⏳ En cours |
| TASK_06_INVESTIGATE_UNKNOWN_CHANNEL.md | ⏳ En cours |
| TASK_01, TASK_03 | ✅ Complétées |

---

## Statistiques

| Catégorie | Avant | Après | Réduction |
|-----------|-------|-------|-----------|
| docs/ | 16 fichiers | 6 fichiers | **-63%** |
| Structure | 4 sous-dossiers | 1 sous-dossier | **-75%** |
| Redondance | ~40% | ~0% | **Éliminée** |

---

## Archive

25+ fichiers archivés incluant les versions originales avant consolidation.
Voir `archive/README.md` pour l'inventaire complet.

---

*Index mis à jour le 2026-02-04 après consolidation majeure*
