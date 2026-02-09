#!/bin/bash
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Token: OK"

# Correct connection IDs
FB_CONN="5558bb48-a4ec-49ba-9e48-b9ca92f3461f"
TT_CONN="292df228-3e1b-4dc2-879e-bd78cc15bcf8"

echo ""
echo "=== Check latest jobs (page 2+3) ==="
curl -s "$API/api/public/v1/jobs?limit=10&offset=10" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    print(f'  Job {j[\"jobId\"]} | conn={j[\"connectionId\"][:12]}... | {j[\"status\"]} | start={j.get(\"startTime\",\"?\")} | rows={j.get(\"rowsSynced\",0)} | bytes={j.get(\"bytesSynced\",0)}')
if not data.get('data'):
    print('  (no more jobs)')
"

echo ""
echo "=== Triggering Facebook sync ==="
FB_RESULT=$(curl -s -X POST "$API/api/public/v1/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"connectionId\":\"$FB_CONN\",\"jobType\":\"sync\"}")
echo "$FB_RESULT" | python3 -m json.tool 2>/dev/null || echo "$FB_RESULT"

echo ""
echo "=== Triggering TikTok sync ==="
TT_RESULT=$(curl -s -X POST "$API/api/public/v1/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"connectionId\":\"$TT_CONN\",\"jobType\":\"sync\"}")
echo "$TT_RESULT" | python3 -m json.tool 2>/dev/null || echo "$TT_RESULT"

echo ""
echo "DONE - syncs triggered"
