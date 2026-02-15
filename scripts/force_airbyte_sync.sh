#!/bin/bash
# Force Airbyte Syncs for Stale Connections
# ==========================================
# Ce script force les syncs manuels pour Facebook et TikTok via Cloud Console SSH

PROJECT="hulken"
ZONE="us-central1-a"
INSTANCE="instance-20260129-133637"

echo "🚀 Force Airbyte Syncs - Facebook & TikTok"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Étape 1: Vérification santé Airbyte${NC}"
HEALTH=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/health" 2>/dev/null)

if [[ $HEALTH == *"\"available\":true"* ]]; then
  echo -e "${GREEN}✅ Airbyte est actif!${NC}"
else
  echo -e "${RED}❌ Airbyte n'est pas accessible. Vérifiez que la VM tourne.${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}Étape 2: Récupération des connection IDs${NC}"

# Get all connections
CONNECTIONS=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/connections/list -H 'Content-Type: application/json' -d '{}'" 2>/dev/null)

# Extract Facebook connection ID
FACEBOOK_ID=$(echo "$CONNECTIONS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    conns = data.get('connections', [])
    for c in conns:
        name = c.get('name', '').lower()
        if 'facebook' in name or 'meta' in name:
            print(c.get('connectionId', ''))
            break
except:
    pass
" 2>/dev/null)

# Extract TikTok connection ID
TIKTOK_ID=$(echo "$CONNECTIONS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    conns = data.get('connections', [])
    for c in conns:
        name = c.get('name', '').lower()
        if 'tiktok' in name:
            print(c.get('connectionId', ''))
            break
except:
    pass
" 2>/dev/null)

if [ -z "$FACEBOOK_ID" ]; then
  echo -e "${RED}❌ Facebook connection non trouvée${NC}"
else
  echo -e "${GREEN}✅ Facebook ID: $FACEBOOK_ID${NC}"
fi

if [ -z "$TIKTOK_ID" ]; then
  echo -e "${RED}❌ TikTok connection non trouvée${NC}"
else
  echo -e "${GREEN}✅ TikTok ID: $TIKTOK_ID${NC}"
fi

echo ""
echo -e "${YELLOW}Étape 3: Force sync Facebook${NC}"

if [ -n "$FACEBOOK_ID" ]; then
  FB_SYNC=$(gcloud compute ssh $INSTANCE \
    --project=$PROJECT \
    --zone=$ZONE \
    --tunnel-through-iap \
    --command="curl -X POST http://localhost:8000/api/v1/connections/sync \
      -H 'Content-Type: application/json' \
      -d '{\"connectionId\": \"$FACEBOOK_ID\"}'" 2>/dev/null)

  FB_JOB_ID=$(echo "$FB_SYNC" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('job', {}).get('id', 'N/A'))
except:
    print('ERROR')
" 2>/dev/null)

  if [[ $FB_JOB_ID != "ERROR" && $FB_JOB_ID != "N/A" ]]; then
    echo -e "${GREEN}✅ Facebook sync démarré! Job ID: $FB_JOB_ID${NC}"
  else
    echo -e "${RED}❌ Erreur lors du démarrage du sync Facebook${NC}"
    echo "$FB_SYNC"
  fi
else
  echo -e "${YELLOW}⚠️  Sync Facebook skipped (connection non trouvée)${NC}"
fi

echo ""
echo -e "${YELLOW}Étape 4: Force sync TikTok${NC}"

if [ -n "$TIKTOK_ID" ]; then
  TT_SYNC=$(gcloud compute ssh $INSTANCE \
    --project=$PROJECT \
    --zone=$ZONE \
    --tunnel-through-iap \
    --command="curl -X POST http://localhost:8000/api/v1/connections/sync \
      -H 'Content-Type: application/json' \
      -d '{\"connectionId\": \"$TIKTOK_ID\"}'" 2>/dev/null)

  TT_JOB_ID=$(echo "$TT_SYNC" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('job', {}).get('id', 'N/A'))
except:
    print('ERROR')
" 2>/dev/null)

  if [[ $TT_JOB_ID != "ERROR" && $TT_JOB_ID != "N/A" ]]; then
    echo -e "${GREEN}✅ TikTok sync démarré! Job ID: $TT_JOB_ID${NC}"
  else
    echo -e "${RED}❌ Erreur lors du démarrage du sync TikTok${NC}"
    echo "$TT_SYNC"
  fi
else
  echo -e "${YELLOW}⚠️  Sync TikTok skipped (connection non trouvée)${NC}"
fi

echo ""
echo -e "${YELLOW}Étape 5: Vérification status des jobs${NC}"
echo "Attente de 10 secondes pour que les jobs démarrent..."
sleep 10

JOBS=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/jobs/list \
    -H 'Content-Type: application/json' \
    -d '{\"configTypes\": [\"sync\"], \"pagination\": {\"pageSize\": 5}}'" 2>/dev/null)

echo "$JOBS" | python3 -c "
import sys, json
from datetime import datetime

try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])

    print('\nDerniers syncs:')
    print('-' * 80)

    for job in jobs[:5]:
        job_info = job.get('job', {})
        job_id = job_info.get('id', 'N/A')
        status = job_info.get('status', 'N/A')

        attempts = job.get('attempts', [])
        if attempts:
            last_attempt = attempts[-1]
            attempt_status = last_attempt.get('status', 'N/A')

            # Get connection info
            created = job_info.get('createdAt', 0)
            if created:
                created_dt = datetime.fromtimestamp(created / 1000)
                created_str = created_dt.strftime('%Y-%m-%d %H:%M:%S')
            else:
                created_str = 'N/A'

            print(f'Job {job_id[:8]}... | Status: {status} | Attempt: {attempt_status} | Created: {created_str}')
        else:
            print(f'Job {job_id[:8]}... | Status: {status} | No attempts yet')

    print('-' * 80)
except Exception as e:
    print(f'Erreur parsing jobs: {e}')
"

echo ""
echo -e "${GREEN}=========================================="
echo "✅ Syncs forcés avec succès!"
echo -e "==========================================${NC}"
echo ""
echo "📊 Prochaines étapes:"
echo "1. Les syncs prennent 5-15 minutes"
echo "2. Vérifie le statut dans Airbyte UI ou re-run ce script"
echo "3. Une fois terminé, run le workflow complet:"
echo "   cd ~/Documents/Projects/Dev_Ops"
echo "   python3 scripts/master_workflow.py"
echo ""
echo "🔍 Pour voir les logs en temps réel:"
echo "   gcloud compute ssh $INSTANCE --project=$PROJECT --zone=$ZONE --tunnel-through-iap"
echo "   docker logs -f airbyte-worker"
echo ""
