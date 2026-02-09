#!/bin/bash
set -e

echo "=== MEMORY ==="
free -h

echo ""
echo "=== SWAP ==="
swapon --show 2>/dev/null || echo "No swap"

echo ""
echo "=== RECENT OOM KILLS (last 3) ==="
sudo dmesg 2>/dev/null | grep -i "out of memory" | tail -3 || echo "No OOM kills found"

echo ""
echo "=== AIRBYTE CONTAINERS ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "docker not found"

echo ""
echo "=== AIRBYTE API: GET CONNECTIONS ==="
CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not get Airbyte token"
  exit 1
fi
echo "Token: OK"

echo ""
echo "=== CONNECTIONS ==="
curl -s "$API/api/public/v1/connections" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('data', []):
    print(f\"  {c['connectionId'][:12]}... | {c['name']} | status={c['status']} | schedule={c.get('schedule',{}).get('scheduleType','?')}\")
"

echo ""
echo "=== LAST 5 JOBS ==="
curl -s "$API/api/public/v1/jobs?limit=5&orderBy=createdAt%7Cdesc" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    print(f\"  Job {j['jobId']} | conn={j['connectionId'][:12]}... | {j['jobType']} | {j['status']} | started={j.get('startTime','?')} | rows={j.get('rowsSynced',0)} | dur={j.get('duration','?')}\")
"
