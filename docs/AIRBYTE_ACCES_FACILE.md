# Accès Airbyte UI - Méthode Qui Fonctionne! 🚀

**Problème:** Le tunnel IAP a des erreurs "Bad file descriptor" avec gcloud SDK

**Solution:** Utiliser **Cloud Console Web SSH** (TOUJOURS fonctionne!)

---

## ⚡ Méthode Rapide (3 minutes)

### Étape 1: Ouvrir Cloud Console

**Lien direct:** https://console.cloud.google.com/compute/instances?project=hulken

Ou:
1. Aller sur https://console.cloud.google.com
2. Sélectionner projet **hulken**
3. Menu ☰ → **Compute Engine** → **VM instances**

---

### Étape 2: Trouver la VM Airbyte

Dans la liste des VMs, chercher:
- **Nom:** `instance-20260129-133637`
- **Zone:** `us-central1-a`

**Statut:**
- ✅ Vert (RUNNING) → OK, continuer
- ⚠️ Gris (TERMINATED) → Cliquer **START** (bouton en haut), attendre 30 sec

---

### Étape 3: SSH dans le Navigateur

1. Dans la ligne de la VM, cliquer bouton **SSH** (colonne "Connect")
2. Une nouvelle fenêtre s'ouvre avec terminal SSH
3. Attendre 5-10 secondes que la connexion s'établisse

**Résultat:** Terminal SSH dans le navigateur! 🎉

---

### Étape 4: Tester Airbyte

Dans le terminal SSH, taper:

```bash
curl http://localhost:8000/api/v1/health
```

**Résultat attendu:**
```json
{"available":true}
```

✅ **Airbyte est actif!**

---

### Étape 5: Lister les Connections

```bash
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

**Résultat:** Liste de toutes tes connections (Shopify, Facebook, TikTok, Google Ads)

---

## 🔄 Forcer un Sync Airbyte

### Via API dans SSH Terminal

**1. Lister les connections et noter l'ID:**
```bash
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool | grep -A2 '"name"'
```

**2. Forcer sync (remplacer CONNECTION_ID):**
```bash
curl -X POST http://localhost:8000/api/v1/connections/sync \
  -H "Content-Type: application/json" \
  -d '{
    "connectionId": "CONNECTION_ID_HERE"
  }'
```

---

## 🖥️ Accéder à l'UI Web Airbyte (Port Forwarding)

### Option A: Via Cloud Console (Recommandé)

**Malheureusement, l'UI web Airbyte (port 8000) ne peut pas être directement accessible via Cloud Console.**

**Solutions:**

1. **Via SSH Web Console + curl** (comme ci-dessus)
   - ✅ Fonctionne toujours
   - ✅ Permet de forcer syncs via API
   - ❌ Pas d'interface graphique

2. **Via Cloud Identity-Aware Proxy (Alternative)**
   ```bash
   # Dans un terminal local
   gcloud compute ssh instance-20260129-133637 \
     --project=hulken \
     --zone=us-central1-a \
     -- -L 8006:localhost:8000 -N -v
   ```
   - ⚠️ Peut avoir des erreurs intermittentes
   - Si fonctionne: Ouvrir http://localhost:8006

3. **Via GCP Cloud Shell** (Stable!)
   - Aller sur: https://shell.cloud.google.com
   - Dans Cloud Shell, exécuter:
     ```bash
     gcloud compute ssh instance-20260129-133637 \
       --project=hulken \
       --zone=us-central1-a \
       --tunnel-through-iap \
       -- -L 8080:localhost:8000 -N &
     ```
   - Cliquer **Web Preview** (icône en haut à droite)
   - Sélectionner **Preview on port 8080**
   - L'UI Airbyte s'ouvre!

---

## 🎯 Cas d'Usage Pratiques

### 1. Vérifier Status des Syncs

**Via API (dans SSH Web Console):**
```bash
# Get all connections
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool > connections.json

# View connections
cat connections.json | grep -E '"name"|"status"|"schedule"' -A1
```

---

### 2. Vérifier Derniers Jobs

```bash
curl -s http://localhost:8000/api/v1/jobs/list \
  -H "Content-Type: application/json" \
  -d '{
    "configTypes": ["sync"],
    "pagination": {"pageSize": 10}
  }' | python3 -m json.tool
```

---

### 3. Activer stream shopify_live_inventory_items

**Via SSH Web Console:**

```bash
# 1. Get connection ID for Shopify
SHOPIFY_CONN_ID=$(curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "import sys, json; conns = json.load(sys.stdin)['connections']; print([c['connectionId'] for c in conns if 'shopify' in c['name'].lower()][0])")

echo "Shopify Connection ID: $SHOPIFY_CONN_ID"

# 2. Get connection details
curl -s http://localhost:8000/api/v1/connections/get \
  -H "Content-Type: application/json" \
  -d "{\"connectionId\": \"$SHOPIFY_CONN_ID\"}" | python3 -m json.tool > shopify_conn.json

# 3. Check if inventory_items stream is enabled
cat shopify_conn.json | grep -i "inventory" -A5

# 4. If not enabled, need to update via UI or complex API call
```

**Note:** Pour activer/désactiver des streams, plus facile via l'UI (Cloud Shell method ci-dessus)

---

## 📊 Dashboard de Monitoring (Alternative)

Puisque l'accès UI est compliqué, créons un script de monitoring:

```bash
#!/bin/bash
# Sauvegarde dans: ~/monitor_airbyte.sh

echo "=== Airbyte Status ==="
curl -s http://localhost:8000/api/v1/health | python3 -m json.tool

echo -e "\n=== Recent Syncs ==="
curl -s http://localhost:8000/api/v1/jobs/list \
  -H "Content-Type: application/json" \
  -d '{"configTypes": ["sync"], "pagination": {"pageSize": 5}}' \
  | python3 -c "
import sys, json
jobs = json.load(sys.stdin)['jobs']
for job in jobs:
    print(f\"Job {job['job']['id']}: {job['job']['status']} - {job.get('attempts', [{}])[-1].get('status', 'N/A')}\")
"

echo -e "\n=== Connection Status ==="
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "
import sys, json
conns = json.load(sys.stdin)['connections']
for c in conns:
    print(f\"{c['name']}: {c['status']}\")
"
```

**Usage:**
```bash
# Dans SSH Web Console
chmod +x monitor_airbyte.sh
./monitor_airbyte.sh
```

---

## ✅ Résumé

### Pour Vérifier Status / Forcer Sync:
1. **Cloud Console Web SSH** (Méthode recommandée)
   - https://console.cloud.google.com/compute/instances?project=hulken
   - Cliquer SSH sur `instance-20260129-133637`
   - Utiliser curl avec API Airbyte

### Pour Accéder UI Graphique:
1. **Cloud Shell + Web Preview** (Méthode recommandée)
   - https://shell.cloud.google.com
   - Port forwarding vers Cloud Shell
   - Web Preview sur port 8080

### Pour Automatisation:
1. **API Airbyte** via scripts
   - Pas besoin d'UI
   - Plus stable
   - Scriptable

---

## 🚨 Troubleshooting

### "Connection refused" dans SSH Console

**Cause:** Airbyte pas démarré

**Fix:**
```bash
# Dans SSH Web Console
sudo docker ps  # Voir si containers tournent

# Si aucun container:
cd /path/to/airbyte  # Trouver le path Airbyte
sudo docker-compose up -d
```

---

### "VM is stopped"

**Fix:**
1. Cloud Console → Compute Engine → VM instances
2. Sélectionner `instance-20260129-133637`
3. Cliquer **START** (bouton en haut)
4. Attendre 30-60 secondes

---

### Tunnel IAP errors persistent

**Ignore them!** Utiliser **Cloud Console Web SSH** ou **Cloud Shell** à la place.

Le tunnel IAP a des bugs connus avec certaines versions de gcloud SDK.

---

## 💡 Recommandation Finale

**Pour tes besoins quotidiens:**

1. **Monitoring Airbyte:**
   - Utiliser le script Python `master_workflow.py`
   - Détecte automatiquement freshness et nouveaux tables
   - Pas besoin d'accéder à l'UI

2. **Forcer Sync si besoin:**
   - Cloud Console Web SSH
   - API curl (exemples ci-dessus)

3. **Configuration (rare):**
   - Cloud Shell + Web Preview
   - Accès UI complet

**90% du temps, tu n'as pas besoin d'accéder à l'UI Airbyte!**

Le workflow automatisé gère tout. 🚀

