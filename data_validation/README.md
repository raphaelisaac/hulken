# Data Validation - Guide d'utilisation

**Date:** 2026-02-13

---

## 🎯 Scripts principaux (à utiliser)

### 1. run_all_checks.py ⭐ **SUPER SCRIPT (RECOMMANDÉ)**

**Ce qu'il fait:** Exécute TOUTES les vérifications en une seule commande.

```bash
# Routine quotidienne (vérifier TOUT)
python data_validation/run_all_checks.py

# Mode détaillé (voir tous les détails)
python data_validation/run_all_checks.py --verbose

# Sauvegarder le rapport
python data_validation/run_all_checks.py --output rapport_quotidien.txt
```

**Vérifications effectuées:**
1. ✅ API vs BigQuery (Shopify, Facebook, TikTok)
2. ✅ Tables vides/nouvelles/stale
3. ✅ Syncs Airbyte (fraîcheur des données)

---

### 2. live_reconciliation.py - Validation API ↔ BigQuery

**Ce qu'il fait:** Compare les données API (sources) avec BigQuery.

```bash
# Vérification complète (toutes plateformes)
python data_validation/live_reconciliation.py

# Shopify seulement
python data_validation/live_reconciliation.py --platform shopify

# Période spécifique
python data_validation/live_reconciliation.py \
  --start-date 2026-02-01 \
  --end-date 2026-02-10

# Mode rapide (sans animation)
python data_validation/live_reconciliation.py --no-animation
```

**Résultat:** Affiche MATCH (vert) ou MISMATCH (rouge) pour chaque métrique.

---

### 3. table_monitoring.py - Détection anomalies

**Ce qu'il fait:** Détecte les tables vides, nouvelles, ou non synchronisées.

```bash
# Première fois: créer la baseline
python data_validation/table_monitoring.py --create-baseline

# Vérification quotidienne
python data_validation/table_monitoring.py --check

# Dataset spécifique
python data_validation/table_monitoring.py --check --dataset ads_data

# Sauvegarder le rapport
python data_validation/table_monitoring.py --check --output report.txt
```

**Résultat:** Liste des tables vides, nouvelles, stale (>48h), manquantes.

---

## 📁 Fichiers utiles (à garder)

| Fichier | Description | Utilisation |
|---------|-------------|-------------|
| `run_all_checks.py` | ⭐ Super script (tout en un) | Routine quotidienne |
| `live_reconciliation.py` | Validation API vs BigQuery | Vérifier cohérence données |
| `table_monitoring.py` | Détection anomalies tables | Détecter nouvelles/vides |
| `anonymize_pii.py` | Anonymisation PII | Gestion données personnelles |
| `config.py` | Configuration | Utilisé par d'autres scripts |
| `soc_checks.py` | SOC compliance | Audits de conformité |
| `.env` | Credentials | **NE JAMAIS COMMITER!** |
| `.env.template` | Template config | Pour nouveaux projets |

---

## 📦 Fichiers archivés (archive_old_scripts/)

Ces fichiers ont été **archivés** car leurs fonctionnalités sont maintenant dans `run_all_checks.py`:

- `reconciliation_check.py` → Fusionné dans run_all_checks
- `reconciliation_app.py` → Fusionné dans run_all_checks
- `reconciliation_report.py` → Pas utilisé
- `validate_data.py` → Fusionné dans run_all_checks
- `sync_watchdog.py` → Fusionné dans run_all_checks
- `*.bat` → Scripts Windows (vous êtes sur Mac)

**Quand supprimer?** Après 3 mois si inutilisés (mai 2026).

---

## 🔄 Workflow quotidien recommandé

```bash
cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops

# 1. Super vérification (TOUT)
python data_validation/run_all_checks.py

# Si tout est ✅ VERT → OK, terminé!
# Si ⚠️ JAUNE ou ❌ ROUGE → Voir section Troubleshooting
```

**Temps:** 2-3 minutes

---

## 🚨 Troubleshooting

### MISMATCH dans API vs BigQuery

| Différence | Cause | Action |
|------------|-------|--------|
| 1-3% | Attribution delay (normal) | Attendre 24h, re-run |
| 3-10% | Sync en cours | Vérifier Airbyte |
| 50%+ | Sync échoué | Forcer sync dans Airbyte |
| API Error | Token expiré | Régénérer token |

**Forcer un sync:**
1. SSH vers VM Airbyte (voir COMPLETE_GUIDE.md)
2. Ouvrir http://localhost:8000
3. Connection concernée → "Sync now"

---

### Table vide détectée

**Exemple:** `shopify_live_inventory_items` = 0 rows

**Causes possibles:**
1. Stream désactivé dans Airbyte (intentionnel)
2. Aucune donnée dans la source
3. Erreur de sync

**Vérifier:**
```bash
# Dans Airbyte UI
# → Connection Shopify
# → Streams tab
# → Vérifier si "inventory_items" est coché
```

---

### Sync Airbyte en retard (>24h)

**Causes:**
1. VM éteinte ou redémarrée
2. Connection échouée
3. Quota API dépassé

**Action:**
1. Vérifier que la VM est allumée
2. Vérifier les logs Airbyte
3. Forcer un sync manuel

---

## 📊 Structure finale data_validation/

```
data_validation/
├── run_all_checks.py           ⭐ SUPER SCRIPT (utiliser celui-ci!)
├── live_reconciliation.py      ✅ API vs BigQuery
├── table_monitoring.py         ✅ Détection tables
├── anonymize_pii.py            ✅ Gestion PII
├── config.py                   ✅ Configuration
├── soc_checks.py               ✅ SOC compliance
├── .env                        🔑 Credentials (protégé)
├── .env.template               📝 Template
├── README.md                   📖 Ce fichier
│
└── archive_old_scripts/        📦 Anciens (ne plus utiliser)
    ├── reconciliation_check.py
    ├── reconciliation_app.py
    ├── reconciliation_report.py
    ├── validate_data.py
    └── sync_watchdog.py
```

---

## ✅ Checklist quotidienne

- [ ] Exécuter `run_all_checks.py`
- [ ] Vérifier que tout est ✅ vert
- [ ] Si ⚠️ jaune → Investiguer
- [ ] Si ❌ rouge → Corriger immédiatement

**Temps:** 5 minutes/jour

---

## 🎉 RÉSULTAT

**AVANT:** 10+ scripts différents, confus, redondants  
**APRÈS:** 1 super script + 2 scripts spécialisés, clair, efficace

*Mis à jour le: 2026-02-13*
