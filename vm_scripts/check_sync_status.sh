#!/bin/bash
# Check sync job status and recent history
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"grant_type\":\"client_credentials\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

echo "=== Recent Jobs (all connections) ==="
curl -s -X GET "$API/api/public/v1/jobs?limit=15&orderBy=updatedAt%7CDESC" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    cid = j.get('connectionId','?')[:12]
    jtype = j.get('jobType','?')
    status = j.get('status','?')
    started = j.get('startTime','?')[:19] if j.get('startTime') else '?'
    ended = j.get('lastUpdatedAt','?')[:19] if j.get('lastUpdatedAt') else '?'
    duration = j.get('duration','?')
    rows = j.get('rowsSynced', '?')
    jid = j.get('jobId', '?')
    print(f'  Job {jid} | conn={cid}... | {jtype} | {status} | started={started} | rows={rows} | dur={duration}')
"

echo ""
echo "=== Facebook connection job history ==="
curl -s -X GET "$API/api/public/v1/jobs?connectionId=5558bb48-a4ec-49ba-9e48-b9ca92f3461f&limit=5&orderBy=updatedAt%7CDESC" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    status = j.get('status','?')
    started = j.get('startTime','?')[:19] if j.get('startTime') else '?'
    duration = j.get('duration','?')
    rows = j.get('rowsSynced', '?')
    bytes_synced = j.get('bytesSynced', '?')
    jid = j.get('jobId', '?')
    print(f'  Job {jid}: {status} | started={started} | rows={rows} | bytes={bytes_synced} | dur={duration}')
"

echo ""
echo "=== Shopify connection job history ==="
curl -s -X GET "$API/api/public/v1/jobs?connectionId=c79a5968-f31b-44b9-b9e6-fa79e630fa40&limit=5&orderBy=updatedAt%7CDESC" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    status = j.get('status','?')
    started = j.get('startTime','?')[:19] if j.get('startTime') else '?'
    duration = j.get('duration','?')
    rows = j.get('rowsSynced', '?')
    jid = j.get('jobId', '?')
    print(f'  Job {jid}: {status} | started={started} | rows={rows} | dur={duration}')
"

echo ""
echo "=== TikTok connection job history ==="
curl -s -X GET "$API/api/public/v1/jobs?connectionId=292df228-3e1b-4dc2-879e-bd78cc15bcf8&limit=5&orderBy=updatedAt%7CDESC" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('data', []):
    status = j.get('status','?')
    started = j.get('startTime','?')[:19] if j.get('startTime') else '?'
    duration = j.get('duration','?')
    rows = j.get('rowsSynced', '?')
    jid = j.get('jobId', '?')
    print(f'  Job {jid}: {status} | started={started} | rows={rows} | dur={duration}')
"

echo ""
echo "=== Check Facebook stream details (last sync) ==="
# Use internal API for more detail
curl -s -X POST "$API/api/v1/jobs/list" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"configTypes":["sync"],"configId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f","pagination":{"pageSize":1,"rowOffset":0}}' 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for j in data.get('jobs', []):
        job = j.get('job', {})
        print(f\"Job ID: {job.get('id')}\")
        print(f\"Status: {job.get('status')}\")
        print(f\"Created: {job.get('createdAt')}\")
        print(f\"Updated: {job.get('updatedAt')}\")
        attempts = j.get('attempts', [])
        print(f\"Attempts: {len(attempts)}\")
        if attempts:
            last = attempts[-1]
            print(f\"Last attempt status: {last.get('status')}\")
            output = last.get('attempt', {}).get('output', {}) or {}
            print(f\"Records synced: {output.get('sync', {}).get('standardSyncSummary', {}).get('recordsSynced', '?') if output.get('sync') else '?'}\")
            fail = last.get('attempt', {}).get('failureSummary', {})
            if fail:
                print(f\"Failure: {fail.get('failures', [{}])[0].get('failureType', '?')}: {fail.get('failures', [{}])[0].get('externalMessage', '?')[:200]}\")
except Exception as e:
    print(f'Could not parse: {e}')
" 2>/dev/null || echo "Internal API not available"

echo ""
echo "=== Done ==="
