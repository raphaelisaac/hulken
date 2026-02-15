# Force Syncs Airbyte - Guide Pratique 🚀

**Date:** 2026-02-15
**Urgence:** HAUTE - Données 4-5 jours en retard!

---

## 📊 État Actuel

| Source | Dernière Donnée | Jours de Retard | Status |
|--------|----------------|-----------------|--------|
| **Facebook Ads** | 2026-02-10 | 5 jours | ⚠️ STALE |
| **TikTok Ads** | 2026-02-11 | 4 jours | ⚠️ STALE |
| **Shopify Orders** | 2026-02-15 | 0 jour | ✅ OK |

**Problème:** Les syncs Airbyte automatiques ne fonctionnent pas depuis 4-5 jours.

---

## ⚡ Solution: Force Sync via Cloud Shell (5 minutes)

### Méthode 1: Via Cloud Shell + Web Preview UI (Recommandé)

#### Étape 1: Ouvrir Cloud Shell
1. Va sur: https://shell.cloud.google.com
2. Attendre que Cloud Shell charge (5-10 sec)

#### Étape 2: Setup Port Forwarding
Dans Cloud Shell, copie-colle cette commande:

```bash
gcloud compute ssh instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a \
  --tunnel-through-iap \
  -- -L 8080:localhost:8000 -N &
```

**Résultat attendu:**
```
Updating project ssh metadata...done.
Waiting for SSH key to propagate.
```

#### Étape 3: Ouvrir Airbyte UI
1. Dans Cloud Shell, en haut à droite, cliquer l'icône **"Web Preview"** (écran avec flèche)
2. Sélectionner **"Preview on port 8080"**
3. Une nouvelle fenêtre s'ouvre avec l'UI Airbyte! 🎉

#### Étape 4: Force Sync Facebook
1. Dans Airbyte UI, cliquer **"Connections"** dans le menu gauche
2. Trouver la connection **Facebook Ads** (ou nom similaire)
3. Cliquer sur la connection pour l'ouvrir
4. En haut à droite, cliquer bouton **"Sync now"**
5. Un popup confirme → Cliquer **"Sync now"** à nouveau

**Résultat:** Le sync démarre! Tu vois la barre de progression.

#### Étape 5: Force Sync TikTok
1. Retour à **"Connections"**
2. Trouver la connection **TikTok Ads**
3. Cliquer dessus
4. Cliquer **"Sync now"**
5. Confirmer

#### Étape 6: Monitorer
1. Aller dans **"Jobs"** dans le menu gauche
2. Tu vois les 2 syncs en cours:
   - Facebook Ads - Running (0m 23s)
   - TikTok Ads - Running (0m 15s)

**Attendre 5-15 minutes** que les syncs se terminent.

**Statut final attendu:**
- Facebook Ads - Succeeded ✅ (12m 34s)
- TikTok Ads - Succeeded ✅ (8m 12s)

---

### Méthode 2: Via Commandes SSH Directes (Sans UI)

Si tu préfères la ligne de commande ou si Web Preview ne fonctionne pas:

#### Étape 1: Lister les Connections

```bash
gcloud compute ssh instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a \
  --tunnel-through-iap \
  --command='curl -s http://localhost:8000/api/v1/connections/list \
    -H "Content-Type: application/json" \
    -d "{}" | python3 -m json.tool | grep -E "\"name\"|\"connectionId\"" -A1'
```

**Note:** L'API peut demander authentification. Si erreur "Unauthorized", utiliser Méthode 1 (UI).

#### Étape 2: Force Sync (si API fonctionne)

Remplace `CONNECTION_ID` par l'ID trouvé ci-dessus:

```bash
gcloud compute ssh instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a \
  --tunnel-through-iap \
  --command='curl -X POST http://localhost:8000/api/v1/connections/sync \
    -H "Content-Type: application/json" \
    -d "{\"connectionId\": \"CONNECTION_ID_HERE\"}"'
```

---

### Méthode 3: Via Cloud Console SSH Web (API uniquement)

Si tu veux juste utiliser l'API sans port forwarding:

1. Va sur: https://console.cloud.google.com/compute/instances?project=hulken
2. Trouve la VM `instance-20260129-133637`
3. Cliquer bouton **SSH** (colonne "Connect")
4. Une fenêtre SSH s'ouvre
5. Dans le terminal SSH, copie-colle:

```bash
# Test health
curl http://localhost:8000/api/v1/health

# List connections
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool

# Force sync (remplace CONNECTION_ID)
curl -X POST http://localhost:8000/api/v1/connections/sync \
  -H "Content-Type: application/json" \
  -d '{"connectionId": "CONNECTION_ID_HERE"}'
```

---

## 🔍 Vérification Après Sync

### Option A: Via BigQuery

Dans 15-20 minutes (après syncs terminés), run:

```bash
bq query --project_id=hulken --use_legacy_sql=false --format=pretty '
SELECT
  "Facebook Ads" AS source,
  MAX(date_start) AS latest_data_date,
  DATE_DIFF(CURRENT_DATE(), MAX(date_start), DAY) AS days_behind
FROM `hulken.ads_data.facebook_ads_insights`

UNION ALL

SELECT
  "TikTok Ads" AS source,
  MAX(DATE(stat_time_day)) AS latest_data_date,
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(stat_time_day)), DAY) AS days_behind
FROM `hulken.ads_data.tiktokads_reports_daily`
'
```

**Résultat attendu:**
```
Facebook Ads  | 2026-02-14 | 1 jour   ← Beaucoup mieux!
TikTok Ads    | 2026-02-14 | 1 jour   ← Beaucoup mieux!
```

(Note: 1 jour de retard est normal - les APIs ont souvent 24h de latence)

### Option B: Via Workflow Script

```bash
cd ~/Documents/Projects/Dev_Ops
python3 scripts/master_workflow.py --skip-reconciliation --skip-pii --skip-report
```

---

## 🚨 Si les Syncs Échouent

### Erreur: "Failed to sync"

**Causes possibles:**

1. **API Rate Limit**
   - Facebook/TikTok ont des limites d'appels API
   - **Solution:** Attendre 1 heure et retry

2. **Invalid Token**
   - Le token API Facebook ou TikTok a expiré
   - **Solution:** Reconnect la source dans Airbyte
     1. Aller dans **"Sources"**
     2. Cliquer sur **"Facebook Marketing"** ou **"TikTok Marketing"**
     3. Cliquer **"Test connection"**
     4. Si erreur, cliquer **"Edit"** → Re-authenticate

3. **Network Error**
   - Problème temporaire de connexion
   - **Solution:** Retry dans 5 minutes

### Voir les Logs d'Erreur

Dans SSH Web Console (Cloud Console ou Cloud Shell):

```bash
# Logs du worker (où les syncs tournent)
sudo docker logs -f airbyte-worker --tail=100

# Logs du server
sudo docker logs -f airbyte-server --tail=100

# Tous les containers
sudo docker ps
```

---

## ✅ Workflow Complet Après Fix

Une fois les syncs terminés et données à jour:

```bash
cd ~/Documents/Projects/Dev_Ops

# Run le workflow complet
python3 scripts/master_workflow.py

# Résultat attendu:
# ✅ Connexion BigQuery OK
# ✅ Réconciliation OK (ou SKIPPED)
# ✅ Détection tables OK
# ✅ Freshness OK (<48h)
# ✅ PII encoding OK
# ✅ Unification tables OK
# ✅ Anomalies détectées et loguées
# ✅ Rapport PowerPoint généré!
```

**Fichier généré:** `reports/Marketing_Performance_Report.pptx`

---

## 🔄 Prévenir les Syncs Stale à l'Avenir

### Option 1: Vérifier Schedule dans Airbyte

1. Dans Airbyte UI, aller dans **"Connections"**
2. Pour chaque connection (Facebook, TikTok):
   - Cliquer sur la connection
   - Vérifier **"Schedule"**
   - Recommandé: **"Every 24 hours"** ou **"Every 12 hours"**

Si Schedule = "Manual", changer à "Every 24 hours":
1. Cliquer **"Settings"** (ou "Edit connection")
2. Section **"Schedule"**
3. Sélectionner **"Scheduled"**
4. Basic Schedule: **24 hours**
5. Sauvegarder

### Option 2: Setup Monitoring Automatique

Créer un cron job qui vérifie freshness quotidiennement:

```bash
# Ouvrir crontab
crontab -e

# Ajouter cette ligne (check à 9h chaque matin)
0 9 * * * cd /Users/raphael_sebbah/Documents/Projects/Dev_Ops && python3 scripts/master_workflow.py --skip-reconciliation --skip-pii --skip-report >> logs/daily_check.log 2>&1
```

**Le workflow détectera automatiquement les tables stales et t'alertera!**

---

## 📞 Aide

**Si tu es bloqué:**

1. **Check VM status:**
   - https://console.cloud.google.com/compute/instances?project=hulken
   - La VM `instance-20260129-133637` doit être **RUNNING** (verte)

2. **Check Airbyte health:**
   ```bash
   gcloud compute ssh instance-20260129-133637 \
     --project=hulken --zone=us-central1-a --tunnel-through-iap \
     --command="curl -s http://localhost:8000/api/v1/health"
   ```
   **Attendu:** `{"available":true}`

3. **Restart Airbyte** (si health = false):
   ```bash
   gcloud compute ssh instance-20260129-133637 \
     --project=hulken --zone=us-central1-a --tunnel-through-iap \
     --command="cd ~/airbyte && sudo docker-compose restart"
   ```

---

## 🎯 Action Immédiate

**COMMENCE MAINTENANT:**

1. Ouvre: https://shell.cloud.google.com
2. Copie-colle:
   ```bash
   gcloud compute ssh instance-20260129-133637 \
     --project=hulken \
     --zone=us-central1-a \
     --tunnel-through-iap \
     -- -L 8080:localhost:8000 -N &
   ```
3. Cliquer **Web Preview** → **Preview on port 8080**
4. Force sync Facebook et TikTok
5. Attendre 15 minutes
6. Reviens ici et run workflow complet

**Dans 20 minutes, tes données seront à jour! 🚀**

