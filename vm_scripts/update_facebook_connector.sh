#!/bin/bash
# =============================================================================
# Update Facebook Marketing Connector in Airbyte
# - Adds hourly breakdown (hourly_stats_aggregated_by_advertiser_time_zone)
# - Optionally changes replication_start_date
#
# Run on the Airbyte VM: instance-20260129-133637 (us-central1-a)
# SSH: gcloud compute ssh instance-20260129-133637 --zone=us-central1-a
# =============================================================================

set -e

# Airbyte API settings
AIRBYTE_API="http://10.96.153.33:8001/api/public/v1"
CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="MRq52n-K30E1dTfjLk7GKuw5cPpjqYgm"  # from .env

# Facebook connection ID
FB_CONNECTION_ID="5558bb48-a4ec-49ba-9e48-b9ca92f3461f"

echo "=========================================="
echo "Facebook Marketing Connector Update"
echo "=========================================="

# Step 1: Get OAuth token
echo ""
echo "[1/4] Getting Airbyte API token..."
TOKEN=$(curl -s -X POST "${AIRBYTE_API}/../../api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\": \"${CLIENT_ID}\", \"client_secret\": \"${CLIENT_SECRET}\"}" \
  | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))")

if [ -z "$TOKEN" ]; then
  echo "[ERROR] Failed to get token. Trying alternative endpoint..."
  TOKEN=$(curl -s -X POST "http://10.96.153.33:8001/api/v1/applications/token" \
    -H "Content-Type: application/json" \
    -d "{\"client_id\": \"${CLIENT_ID}\", \"client_secret\": \"${CLIENT_SECRET}\"}" \
    | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))")
fi

if [ -z "$TOKEN" ]; then
  echo "[ERROR] Could not obtain API token"
  exit 1
fi
echo "[OK] Token obtained"

# Step 2: Get current connection config
echo ""
echo "[2/4] Reading current Facebook connection config..."
CURRENT_CONFIG=$(curl -s -X GET "${AIRBYTE_API}/connections/${FB_CONNECTION_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

echo "$CURRENT_CONFIG" | python3 -m json.tool > /tmp/fb_connection_current.json 2>/dev/null
echo "[OK] Current config saved to /tmp/fb_connection_current.json"

# Step 3: Get source ID from connection
SOURCE_ID=$(echo "$CURRENT_CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sourceId', ''))")
echo "Source ID: $SOURCE_ID"

# Step 4: Get current source config
echo ""
echo "[3/4] Reading current Facebook source config..."
SOURCE_CONFIG=$(curl -s -X GET "${AIRBYTE_API}/sources/${SOURCE_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

echo "$SOURCE_CONFIG" | python3 -m json.tool > /tmp/fb_source_current.json 2>/dev/null
echo "[OK] Source config saved to /tmp/fb_source_current.json"

# Display current settings
echo ""
echo "Current settings:"
echo "$SOURCE_CONFIG" | python3 -c "
import sys, json
config = json.load(sys.stdin)
sc = config.get('configuration', {})
print(f\"  Start date: {sc.get('start_date', 'NOT SET')}\")
print(f\"  Account IDs: {sc.get('account_ids', 'NOT SET')}\")
# Check for insights streams with breakdowns
print(f\"  Action breakdowns: {sc.get('action_breakdowns_allow_empty', 'default')}\")
insights = sc.get('custom_insights', [])
if insights:
    for i, ins in enumerate(insights):
        print(f\"  Custom insight {i}: {ins.get('name', '?')} - breakdowns: {ins.get('breakdowns', [])}\")
else:
    print('  No custom insights configured')
"

echo ""
echo "=========================================="
echo "REVIEW THE CURRENT CONFIG ABOVE"
echo "=========================================="
echo ""
echo "To add hourly breakdown, you need to:"
echo "1. Go to Airbyte UI: http://localhost:8000"
echo "2. Navigate to Sources > Facebook Marketing"
echo "3. In the streams configuration, find 'ads_insights'"
echo "4. Add breakdown: hourly_stats_aggregated_by_advertiser_time_zone"
echo ""
echo "Or use the API (Step 4 below)."
echo ""
read -p "Do you want to update via API? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
  echo "Aborted. Review /tmp/fb_source_current.json manually."
  exit 0
fi

# Step 4: Update source with hourly breakdown
echo ""
echo "[4/4] Updating Facebook source..."

# Read current config and modify
python3 << 'PYEOF'
import json, sys

with open('/tmp/fb_source_current.json') as f:
    source = json.load(f)

config = source.get('configuration', {})

# Option A: Change start_date (uncomment to go further back)
# config['start_date'] = '2023-01-01'
# print(f"  Updated start_date to: {config['start_date']}")

# Option B: Add custom insights with hourly breakdown
custom_insights = config.get('custom_insights', [])

# Check if hourly insight already exists
hourly_exists = any(
    'hourly_stats_aggregated_by_advertiser_time_zone' in ins.get('breakdowns', [])
    for ins in custom_insights
)

if hourly_exists:
    print("  Hourly breakdown already configured!")
else:
    hourly_insight = {
        "name": "ads_insights_hourly",
        "fields": ["spend", "impressions", "clicks", "actions", "action_values", "reach", "cpc", "cpm", "ctr"],
        "breakdowns": ["hourly_stats_aggregated_by_advertiser_time_zone"],
        "action_breakdowns": [],
        "start_date": config.get('start_date', '2024-02-01'),
        "end_date": "",
        "insights_lookback_window": 28,
        "level": "ad"
    }
    custom_insights.append(hourly_insight)
    config['custom_insights'] = custom_insights
    print(f"  Added hourly insight stream: ads_insights_hourly")

# Save updated config
update_payload = {
    "configuration": config
}
with open('/tmp/fb_source_update.json', 'w') as f:
    json.dump(update_payload, f, indent=2)

print("  Update payload saved to /tmp/fb_source_update.json")
PYEOF

# Apply the update
echo ""
echo "Applying update..."
UPDATE_RESULT=$(curl -s -X PATCH "${AIRBYTE_API}/sources/${SOURCE_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d @/tmp/fb_source_update.json)

echo "$UPDATE_RESULT" | python3 -c "
import sys, json
try:
    result = json.load(sys.stdin)
    if 'sourceId' in result:
        print('[OK] Source updated successfully!')
        print(f\"  Source: {result.get('name', '?')}\")
    else:
        print(f'[ERROR] {json.dumps(result, indent=2)}')
except:
    print('[ERROR] Could not parse response')
"

echo ""
echo "=========================================="
echo "NEXT STEPS:"
echo "1. Go to Airbyte UI and trigger a new sync"
echo "2. The new stream 'ads_insights_hourly' will appear in BigQuery"
echo "3. Query it: SELECT * FROM hulken.ads_data.ads_insights_hourly LIMIT 10"
echo "=========================================="
