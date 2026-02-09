#!/bin/bash
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "Token: OK"

echo ""
echo "=== ALL CONNECTIONS (full detail) ==="
curl -s "$API/api/public/v1/connections" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null

echo ""
echo "=== RECENT JOBS ==="
curl -s "$API/api/public/v1/jobs?limit=10" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null | head -120
