#!/bin/bash
# Fix Airbyte configuration issues
# Run ON the Airbyte VM
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

echo "=== Getting auth token ==="
TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"grant_type\":\"client_credentials\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
echo "Token: OK"

echo ""
echo "=== Step 1: List ALL connections ==="
curl -s -X GET "$API/api/public/v1/connections" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('data', []):
    print(f\"  ID: {c['connectionId']}\")
    print(f\"  Name: {c['name']}\")
    print(f\"  Status: {c['status']}\")
    print(f\"  Schedule: {c.get('schedule', {}).get('scheduleType', '?')}\")
    print(f\"  SrcID: {c.get('sourceId', '?')}\")
    print(f\"  DstID: {c.get('destinationId', '?')}\")
    print('  ---')
"

echo ""
echo "=== Step 2: Get Facebook Marketing connection details ==="
curl -s -X GET "$API/api/public/v1/connections/5558bb48-a4ec-49ba-9e48-b9ca92f3461f" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Name: {data.get('name', '?')}\")
print(f\"Status: {data.get('status', '?')}\")
print(f\"Namespace: {data.get('namespaceDefinition', '?')}\")
print(f\"Namespace format: {data.get('namespaceFormat', '?')}\")
print(f\"Prefix: {data.get('prefix', '?')}\")
print()
print('Streams:')
for s in data.get('configurations', {}).get('streams', []):
    name = s.get('name', '?')
    sync_mode = s.get('syncMode', '?')
    print(f\"  {name}: syncMode={sync_mode}\")
"

echo ""
echo "=== Step 3: Get TikTok connection details ==="
curl -s -X GET "$API/api/public/v1/connections/292df228-3e1b-4dc2-879e-bd78cc15bcf8" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Name: {data.get('name', '?')}\")
print(f\"Status: {data.get('status', '?')}\")
print(f\"Prefix: {data.get('prefix', '?')}\")
print()
print('Streams:')
for s in data.get('configurations', {}).get('streams', []):
    name = s.get('name', '?')
    sync_mode = s.get('syncMode', '?')
    print(f\"  {name}: syncMode={sync_mode}\")
"

echo ""
echo "=== Step 4: Check for legacy/duplicate Facebook connections ==="
curl -s -X GET "$API/api/public/v1/connections" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
fb_connections = [c for c in data.get('data', []) if 'facebook' in c.get('name','').lower() or 'fb' in c.get('name','').lower()]
print(f'Found {len(fb_connections)} Facebook connection(s):')
for c in fb_connections:
    print(f\"  {c['connectionId']}: {c['name']} (status={c['status']})\")
non_fb = [c for c in data.get('data', []) if c['connectionId'] not in [fc['connectionId'] for fc in fb_connections] and c['connectionId'] not in ['c79a5968-f31b-44b9-b9e6-fa79e630fa40', '292df228-3e1b-4dc2-879e-bd78cc15bcf8']]
if non_fb:
    print(f'Other unknown connections:')
    for c in non_fb:
        print(f\"  {c['connectionId']}: {c['name']} (status={c['status']})\")
"

echo ""
echo "=== Step 5: Check Airbyte notification settings ==="
# Try the internal API for workspace settings
curl -s -X POST "$API/api/v1/workspaces/list" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for w in data.get('workspaces', []):
        print(f\"Workspace: {w.get('name', '?')}\")
        print(f\"  ID: {w.get('workspaceId', '?')}\")
        notifs = w.get('notifications', [])
        print(f\"  Notifications configured: {len(notifs)}\")
        for n in notifs:
            print(f\"    Type: {n.get('notificationType', '?')}\")
except:
    print('Could not read workspace settings via v1 API')
" 2>/dev/null || echo "Workspace API not available"

echo ""
echo "=== Diagnostic complete ==="
