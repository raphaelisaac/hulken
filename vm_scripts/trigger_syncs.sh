#!/bin/bash
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Token: OK"

# Connection IDs
FB_CONN="5558bb48-a4ed-4ef2-9927-b3fda41b0674"
TT_CONN="292df228-3e18-437f-b1e7-3c9e91c05fd1"

echo ""
echo "=== Recent jobs (raw) ==="
curl -s "$API/api/public/v1/jobs?limit=5&orderBy=createdAt%7Cdesc" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null | head -80

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
echo "DONE"
