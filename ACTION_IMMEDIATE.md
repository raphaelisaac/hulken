# Action Immédiate - Fix Data Stale & Attribution 🚨

**Date:** 2026-02-13
**Priorité:** CRITIQUE

---

## 🔥 Problèmes Critiques Détectés

### 1. Data Stale (Syncs Airbyte en retard)
- **Facebook Ads:** 109 heures sans sync (4.5 jours) ❌
- **TikTok Ads:** 67 heures sans sync (2.8 jours) ❌

### 2. Attribution Cassée
- **Facebook:** $38,000 dépensés, $0 revenue attribué ❌
- **TikTok:** $14,000 dépensés, $0 revenue attribué ❌

**Total perdu en visibilité:** $52,000 de spend sans tracking! 💸

---

## ⚡ Solution Immédiate (10 minutes)

### Étape 1: Forcer les Syncs Airbyte (2 min)

**Exécute ce script:**
```bash
cd ~/Documents/Projects/Hulken
./scripts/force_airbyte_sync.sh
```

**Ce qu'il fait:**
1. ✅ Vérifie que Airbyte est actif
2. ✅ Trouve les connection IDs Facebook et TikTok
3. ✅ Force les syncs manuels via API
4. ✅ Affiche les job IDs pour suivi

**Résultat attendu:**
```
✅ Facebook sync démarré! Job ID: abc123...
✅ TikTok sync démarré! Job ID: xyz789...
```

---

### Étape 2: Monitorer les Syncs (5-15 min)

**Pendant que les syncs tournent:**
```bash
# Option A: Monitor script (refresh manuel)
./scripts/monitor_airbyte_syncs.sh

# Option B: Auto-refresh toutes les 30 secondes
watch -n 30 ./scripts/monitor_airbyte_syncs.sh
```

**Attendre que tu voies:**
```
Job abc123... | Status: succeeded ✅ | Durée: 8m 23s
Job xyz789... | Status: succeeded ✅ | Durée: 12m 45s
```

---

### Étape 3: Vérifier les Données dans BigQuery (3 min)

**Une fois les syncs complétés, vérifier freshness:**
```bash
cd ~/Documents/Projects/Dev_Ops
python3 scripts/master_workflow.py --skip-reconciliation --skip-pii --skip-report
```

Ou manuellement dans BigQuery:
```sql
-- Check freshness
SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_sync,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MILLIS(last_modified_time), HOUR) AS hours_since_sync
FROM `hulken.ads_data.__TABLES__`
WHERE table_id IN ('facebook_ads_insights', 'tiktok_ads_reports_daily')
ORDER BY hours_since_sync DESC;
```

**Résultat attendu:** `hours_since_sync` < 1 heure ✅

---

### Étape 4: Vérifier Attribution (2 min)

**Check si revenue est maintenant visible:**
```sql
SELECT
  date,
  channel,
  ad_spend,
  revenue,
  ad_clicks,
  SAFE_DIVIDE(revenue, ad_spend) AS roas
FROM `hulken.ads_data.marketing_unified`
WHERE channel IN ('Facebook Ads', 'TikTok Ads')
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
ORDER BY date DESC, channel;
```

**Si revenue est encore à $0:**
- ⚠️ Problème d'attribution (UTM manquants, Pixel cassé)
- 👉 Passer à la Section "Fix Attribution" ci-dessous

**Si revenue apparaît:**
- ✅ Data sync OK, attribution fonctionne!
- 👉 Run le workflow complet pour mettre à jour les rapports

---

## 🔧 Fix Attribution (Si Revenue Encore à $0)

### Problèmes Possibles

#### A. UTM Parameters Manquants

**Check dans Shopify:**
```sql
SELECT
  order_id,
  order_created_at,
  order_value,
  utm_source,
  utm_medium,
  utm_campaign
FROM `hulken.ads_data.shopify_unified`
WHERE order_created_at >= CURRENT_DATE() - 7
  AND order_value > 0
ORDER BY order_created_at DESC
LIMIT 100;
```

**Si utm_source = NULL pour la plupart:**
- Problème: Pas de tracking UTM sur les ads
- Fix: Vérifier les templates d'URL dans Facebook Ads Manager et TikTok Ads Manager

---

#### B. Facebook Pixel Cassé

**Vérifier dans Facebook Events Manager:**
1. Va sur: https://business.facebook.com/events_manager2/
2. Sélectionner ton Pixel
3. Vérifier "Recent Events" (dernières 24h)

**Si aucun événement "Purchase":**
- Problème: Pixel pas installé ou tracking cassé
- Fix: Réinstaller le Pixel sur Shopify

**Comment fix:**
```
1. Shopify Admin → Settings → Apps and sales channels
2. Facebook & Instagram → Settings
3. Reconnect Pixel
4. Tester avec Facebook Pixel Helper extension
```

---

#### C. TikTok Pixel Cassé

**Vérifier dans TikTok Events Manager:**
1. Va sur: https://ads.tiktok.com/i18n/events_manager
2. Vérifier "Recent Events"

**Si aucun événement "CompletePayment":**
- Problème: Pixel pas configuré
- Fix: Réinstaller le TikTok Pixel

---

#### D. Conversion API Non Configurée

**Facebook & TikTok ont besoin de Conversion API (CAPI) en plus du Pixel pour attribution fiable.**

**Quick check:**
```sql
-- Compare Pixel events vs API events
SELECT
  COUNT(*) AS total_purchases,
  COUNTIF(attribution_source = 'pixel') AS pixel_purchases,
  COUNTIF(attribution_source = 'api') AS api_purchases
FROM `hulken.ads_data.facebook_conversions`
WHERE event_name = 'Purchase'
  AND date >= CURRENT_DATE() - 7;
```

**Si api_purchases = 0:**
- Problème: Conversion API pas configurée
- Fix: Setup CAPI dans Shopify

**Guide:** [docs/SETUP_CONVERSION_API.md](docs/SETUP_CONVERSION_API.md) (à créer)

---

## 📊 Run Workflow Complet

**Une fois data sync + attribution OK:**

```bash
cd ~/Documents/Projects/Dev_Ops
python3 scripts/master_workflow.py
```

**Durée:** 5-10 minutes

**Résultat:**
- ✅ Tables unifiées mises à jour
- ✅ Anomalies détectées et loguées
- ✅ PowerPoint généré avec données fraîches
- ✅ Fichier: `reports/Marketing_Performance_Report.pptx`

---

## 🎯 Checklist Complète

### Immédiat (maintenant!)
- [ ] Run `./scripts/force_airbyte_sync.sh` pour Facebook & TikTok
- [ ] Attendre 5-15 min que syncs se terminent
- [ ] Vérifier freshness < 1h dans BigQuery

### Court terme (aujourd'hui)
- [ ] Vérifier attribution (revenue visible dans marketing_unified?)
- [ ] Si attribution cassée, vérifier Pixel Facebook & TikTok
- [ ] Run workflow complet (`python3 master_workflow.py`)
- [ ] Vérifier PowerPoint généré

### Moyen terme (cette semaine)
- [ ] Fix attribution si encore cassée (UTM, Pixel, CAPI)
- [ ] Setup cron job pour workflow quotidien
- [ ] Créer dashboard Looker Studio ([docs/LOOKER_10MIN_QUICKSTART.md](docs/LOOKER_10MIN_QUICKSTART.md))
- [ ] Activer shopify_live_inventory_items stream dans Airbyte

### Long terme (ce mois)
- [ ] Ajouter Amazon Ads à Airbyte ([docs/AMAZON_ADS_AIRBYTE_SETUP.md](docs/AMAZON_ADS_AIRBYTE_SETUP.md))
- [ ] Connecter GA4 pour sessions/devices
- [ ] Connecter Fairing pour surveys
- [ ] Setup alerting automatique pour data stale

---

## 🚨 Troubleshooting

### "force_airbyte_sync.sh ne trouve pas les connections"

**Solution:** Les connection names peuvent varier. Exécute manuellement:
```bash
# SSH dans la VM
gcloud compute ssh instance-20260129-133637 \
  --project=hulken \
  --zone=us-central1-a \
  --tunnel-through-iap

# Liste toutes les connections
curl -s http://localhost:8000/api/v1/connections/list \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool | grep -E '"name"|"connectionId"' -A1
```

Note le `connectionId` et force sync manuellement:
```bash
curl -X POST http://localhost:8000/api/v1/connections/sync \
  -H "Content-Type: application/json" \
  -d '{"connectionId": "PASTE_ID_HERE"}'
```

---

### "Syncs échouent avec erreur API"

**Vérifier les logs:**
```bash
# SSH dans VM
gcloud compute ssh instance-20260129-133637 \
  --project=hulken --zone=us-central1-a --tunnel-through-iap

# Voir logs Airbyte worker
sudo docker logs -f airbyte-worker --tail=100
```

**Erreurs communes:**
- `API rate limit exceeded` → Attendre 1h et retry
- `Invalid access token` → Reconnect la source dans Airbyte UI
- `Permission denied` → Vérifier permissions API dans Facebook/TikTok

---

### "Revenue toujours à $0 après sync"

**C'est un problème d'attribution, pas de sync.**

1. Vérifier que les orders Shopify ont des UTM:
   ```sql
   SELECT COUNT(*) AS orders_with_utm
   FROM `hulken.ads_data.shopify_unified`
   WHERE order_created_at >= CURRENT_DATE() - 7
     AND utm_source IS NOT NULL;
   ```

2. Si 0 orders avec UTM → Fix tracking URLs dans ads
3. Si >0 orders avec UTM mais revenue = 0 → Vérifier logic marketing_unified join

---

## 📞 Support

**Logs à checker:**
- Airbyte syncs: `sudo docker logs airbyte-worker`
- Workflow: `~/Documents/Projects/Dev_Ops/logs/workflow_cron.log`
- Anomalies: `~/Documents/Projects/Dev_Ops/logs/anomalies_*.txt`

**Files utiles:**
- Guide Airbyte access: [docs/AIRBYTE_ACCES_FACILE.md](docs/AIRBYTE_ACCES_FACILE.md)
- Comprendre les données: [docs/COMPRENDRE_LES_DONNEES.md](docs/COMPRENDRE_LES_DONNEES.md)
- Workflow complet: [WORKFLOW_COMPLET.md](WORKFLOW_COMPLET.md)

---

## ✅ Success Criteria

**Tu sauras que c'est fixé quand:**

1. ✅ Freshness < 24h pour Facebook et TikTok
2. ✅ Revenue > $0 dans `marketing_unified` pour Facebook/TikTok
3. ✅ ROAS calculé et cohérent (revenue / spend)
4. ✅ PowerPoint généré avec métriques à jour
5. ✅ Aucune anomalie "suspicious_zero" pour Facebook/TikTok

---

## 🚀 Action NOW!

**Copie-colle cette commande maintenant:**

```bash
cd ~/Documents/Projects/Hulken && ./scripts/force_airbyte_sync.sh
```

**Pendant que ça tourne, prépare un café ☕ - Retour dans 10 minutes!**

