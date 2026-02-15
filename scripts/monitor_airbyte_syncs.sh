#!/bin/bash
# Monitor Airbyte Syncs Status
# =============================
# Vérifie le statut des syncs Airbyte en temps réel

PROJECT="hulken"
ZONE="us-central1-a"
INSTANCE="instance-20260129-133637"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 Airbyte Sync Monitor${NC}"
echo "======================="
echo ""

# Check Airbyte health
echo -e "${YELLOW}Status Airbyte:${NC}"
HEALTH=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/health" 2>/dev/null)

if [[ $HEALTH == *"\"available\":true"* ]]; then
  echo -e "${GREEN}✅ Airbyte actif${NC}"
else
  echo -e "${RED}❌ Airbyte non accessible${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}Derniers syncs (5 plus récents):${NC}"
echo ""

# Get recent jobs
JOBS=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/jobs/list \
    -H 'Content-Type: application/json' \
    -d '{\"configTypes\": [\"sync\"], \"pagination\": {\"pageSize\": 10}}'" 2>/dev/null)

echo "$JOBS" | python3 -c "
import sys, json
from datetime import datetime, timedelta

try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])

    if not jobs:
        print('Aucun job trouvé')
        sys.exit(0)

    # Status colors mapping
    status_symbols = {
        'succeeded': '✅',
        'running': '🔄',
        'pending': '⏳',
        'failed': '❌',
        'cancelled': '🚫',
        'incomplete': '⚠️'
    }

    print(f\"{'Job ID':<12} {'Connection':<20} {'Status':<12} {'Durée':<10} {'Créé à':<20} {'Complété à':<20}\")
    print('-' * 120)

    for job in jobs[:10]:
        job_info = job.get('job', {})
        job_id = job_info.get('id', 'N/A')[:8]
        status = job_info.get('status', 'N/A').lower()

        attempts = job.get('attempts', [])
        attempt_status = 'N/A'
        duration = 'N/A'
        completed_str = 'N/A'

        if attempts:
            last_attempt = attempts[-1]
            attempt_status = last_attempt.get('status', 'N/A').lower()

            started = last_attempt.get('createdAt', 0)
            ended = last_attempt.get('endedAt', 0)

            if started and ended:
                duration_sec = (ended - started) / 1000
                duration_min = int(duration_sec / 60)
                duration_sec_mod = int(duration_sec % 60)
                duration = f\"{duration_min}m {duration_sec_mod}s\"

                completed_dt = datetime.fromtimestamp(ended / 1000)
                completed_str = completed_dt.strftime('%Y-%m-%d %H:%M:%S')
            elif started:
                # Still running
                now = datetime.now().timestamp() * 1000
                duration_sec = (now - started) / 1000
                duration_min = int(duration_sec / 60)
                duration = f\"{duration_min}m (en cours)\"

        created = job_info.get('createdAt', 0)
        if created:
            created_dt = datetime.fromtimestamp(created / 1000)
            created_str = created_dt.strftime('%Y-%m-%d %H:%M:%S')
        else:
            created_str = 'N/A'

        # Get connection name (not always available in job response)
        connection_name = 'N/A'

        symbol = status_symbols.get(attempt_status, '❓')

        print(f\"{job_id:<12} {connection_name:<20} {symbol} {attempt_status:<10} {duration:<10} {created_str:<20} {completed_str:<20}\")

    print('-' * 120)

except Exception as e:
    print(f'Erreur: {e}')
    import traceback
    traceback.print_exc()
"

echo ""
echo -e "${YELLOW}Connections status:${NC}"
echo ""

# Get connections status
CONNECTIONS=$(gcloud compute ssh $INSTANCE \
  --project=$PROJECT \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command="curl -s http://localhost:8000/api/v1/connections/list \
    -H 'Content-Type: application/json' \
    -d '{}'" 2>/dev/null)

echo "$CONNECTIONS" | python3 -c "
import sys, json
from datetime import datetime

try:
    data = json.load(sys.stdin)
    conns = data.get('connections', [])

    if not conns:
        print('Aucune connection trouvée')
        sys.exit(0)

    print(f\"{'Connection Name':<30} {'Status':<12} {'Schedule':<20} {'Latest Job':<15}\")
    print('-' * 100)

    for conn in conns:
        name = conn.get('name', 'N/A')
        status = conn.get('status', 'N/A')

        schedule = conn.get('schedule', {})
        if schedule:
            schedule_type = schedule.get('scheduleType', 'manual')
            if schedule_type == 'manual':
                schedule_str = 'Manual'
            elif schedule_type == 'basic':
                units = schedule.get('basicSchedule', {}).get('units', 'N/A')
                time_unit = schedule.get('basicSchedule', {}).get('timeUnit', 'N/A')
                schedule_str = f\"Every {units} {time_unit}\"
            else:
                schedule_str = schedule_type
        else:
            schedule_str = 'Manual'

        # Latest sync job (would need additional API call to get this)
        latest_job = 'N/A'

        status_symbol = '✅' if status == 'active' else '❌'

        print(f\"{name:<30} {status_symbol} {status:<10} {schedule_str:<20} {latest_job:<15}\")

    print('-' * 100)

except Exception as e:
    print(f'Erreur: {e}')
"

echo ""
echo -e "${BLUE}=========================================="
echo "Pour forcer un nouveau sync:"
echo "  ./scripts/force_airbyte_sync.sh"
echo ""
echo "Pour voir ce monitor en continu (refresh 30s):"
echo "  watch -n 30 ./scripts/monitor_airbyte_syncs.sh"
echo -e "==========================================${NC}"
echo ""
