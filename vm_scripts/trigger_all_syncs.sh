#!/bin/bash
# Trigger all Airbyte syncs - run this ON the Airbyte VM
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
echo "=== Triggering syncs ==="

# Facebook Marketing
echo -n "  Facebook Marketing: "
RESULT=$(curl -s -X POST "$API/api/public/v1/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"connectionId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f","jobType":"sync"}')
echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f\"job={d.get('jobId','?')} status={d.get('status','?')}\")" 2>/dev/null || echo "$RESULT" | head -c 200

# Shopify
echo -n "  Shopify: "
RESULT=$(curl -s -X POST "$API/api/public/v1/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"connectionId":"c79a5968-f31b-44b9-b9e6-fa79e630fa40","jobType":"sync"}')
echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f\"job={d.get('jobId','?')} status={d.get('status','?')}\")" 2>/dev/null || echo "$RESULT" | head -c 200

# TikTok Marketing
echo -n "  TikTok Marketing: "
RESULT=$(curl -s -X POST "$API/api/public/v1/jobs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"connectionId":"292df228-3e1b-4dc2-879e-bd78cc15bcf8","jobType":"sync"}')
echo "$RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f\"job={d.get('jobId','?')} status={d.get('status','?')}\")" 2>/dev/null || echo "$RESULT" | head -c 200

echo ""
echo "=== All syncs triggered ==="
