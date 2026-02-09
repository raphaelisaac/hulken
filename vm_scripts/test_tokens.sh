#!/bin/bash
# Test API tokens for Facebook and TikTok
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"grant_type\":\"client_credentials\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

echo "=== Extracting source configs from Airbyte ==="

# Get Facebook source config
echo ""
echo "--- Facebook Source ---"
FB_SRC_ID="47e47ea7-863f-43ba-9055-240a0b0a9a9f"
FB_CONFIG=$(curl -s -X GET "$API/api/public/v1/sources/$FB_SRC_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")
echo "$FB_CONFIG" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Source name: {data.get('name', '?')}\")
print(f\"Source type: {data.get('sourceType', '?')}\")
config = data.get('configuration', {})
print(f\"Account ID: {config.get('account_ids', config.get('account_id', '?'))}\")
access_token = config.get('access_token', '')
if access_token:
    print(f\"Access token: {access_token[:15]}...{access_token[-10:]} (length={len(access_token)})\")
else:
    print('Access token: NOT FOUND')
# Save token for testing
with open('/tmp/fb_token.txt', 'w') as f:
    f.write(access_token)
account_ids = config.get('account_ids', [config.get('account_id', '')])
if isinstance(account_ids, list) and account_ids:
    with open('/tmp/fb_account.txt', 'w') as f:
        f.write(str(account_ids[0]))
elif isinstance(account_ids, str):
    with open('/tmp/fb_account.txt', 'w') as f:
        f.write(account_ids)
"

# Test Facebook token directly
echo ""
echo "--- Testing Facebook Token ---"
FB_TOKEN=$(cat /tmp/fb_token.txt 2>/dev/null)
FB_ACCOUNT=$(cat /tmp/fb_account.txt 2>/dev/null)
if [ -n "$FB_TOKEN" ]; then
    echo "Testing against Facebook Graph API..."

    # Test 1: Basic token validation
    echo -n "  Token validity: "
    FB_ME=$(curl -s "https://graph.facebook.com/v21.0/me?access_token=$FB_TOKEN")
    echo "$FB_ME" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print(f\"FAILED - {data['error'].get('message', '?')}\")
    print(f\"  Error type: {data['error'].get('type', '?')}\")
    print(f\"  Error code: {data['error'].get('code', '?')}\")
else:
    print(f\"OK - User: {data.get('name', data.get('id', '?'))}\")
"

    # Test 2: Can we access the ad account?
    if [ -n "$FB_ACCOUNT" ]; then
        echo -n "  Ad account access (act_$FB_ACCOUNT): "
        FB_ACCT=$(curl -s "https://graph.facebook.com/v21.0/act_${FB_ACCOUNT}?fields=name,account_status&access_token=$FB_TOKEN")
        echo "$FB_ACCT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print(f\"FAILED - {data['error'].get('message', '?')}\")
else:
    status_map = {1: 'ACTIVE', 2: 'DISABLED', 3: 'UNSETTLED', 7: 'PENDING_RISK_REVIEW', 8: 'PENDING_SETTLEMENT', 9: 'IN_GRACE_PERIOD', 100: 'PENDING_CLOSURE', 101: 'CLOSED', 201: 'ANY_ACTIVE', 202: 'ANY_CLOSED'}
    status = status_map.get(data.get('account_status'), data.get('account_status'))
    print(f\"OK - {data.get('name', '?')} (status={status})\")
"

        # Test 3: Can we pull insights?
        echo -n "  Insights API access: "
        FB_INSIGHTS=$(curl -s "https://graph.facebook.com/v21.0/act_${FB_ACCOUNT}/insights?date_preset=yesterday&fields=spend,impressions&access_token=$FB_TOKEN")
        echo "$FB_INSIGHTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print(f\"FAILED - {data['error'].get('message', '?')}\")
elif 'data' in data:
    if data['data']:
        row = data['data'][0]
        print(f\"OK - Yesterday: spend={row.get('spend','?')}, impressions={row.get('impressions','?')}\")
    else:
        print('OK but no data for yesterday (might be normal if no spend)')
else:
    print(f'Unexpected response: {str(data)[:200]}')
"
    fi
else
    echo "  No Facebook token found in Airbyte config"
fi

# Get TikTok source config
echo ""
echo "--- TikTok Source ---"
TT_SRC_ID="9cbb7b26-6bf9-42a1-94a3-1c643ef7fa91"
TT_CONFIG=$(curl -s -X GET "$API/api/public/v1/sources/$TT_SRC_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")
echo "$TT_CONFIG" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Source name: {data.get('name', '?')}\")
print(f\"Source type: {data.get('sourceType', '?')}\")
config = data.get('configuration', {})
creds = config.get('credentials', {})
access_token = creds.get('access_token', config.get('access_token', ''))
advertiser_id = config.get('advertiser_id', config.get('environment', {}).get('advertiser_id', ''))
print(f\"Advertiser ID: {advertiser_id}\")
if access_token:
    print(f\"Access token: {access_token[:15]}...{access_token[-10:]} (length={len(access_token)})\")
else:
    print('Access token: NOT FOUND')
with open('/tmp/tt_token.txt', 'w') as f:
    f.write(access_token)
with open('/tmp/tt_adv.txt', 'w') as f:
    f.write(str(advertiser_id))
"

# Test TikTok token
echo ""
echo "--- Testing TikTok Token ---"
TT_TOKEN=$(cat /tmp/tt_token.txt 2>/dev/null)
TT_ADV=$(cat /tmp/tt_adv.txt 2>/dev/null)
if [ -n "$TT_TOKEN" ]; then
    echo "Testing against TikTok Marketing API..."

    echo -n "  Advertiser info: "
    TT_INFO=$(curl -s -X GET "https://business-api.tiktok.com/open_api/v1.3/advertiser/info/?advertiser_ids=[%22$TT_ADV%22]" \
      -H "Access-Token: $TT_TOKEN")
    echo "$TT_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
code = data.get('code', '?')
msg = data.get('message', '?')
if code == 0:
    advs = data.get('data', {}).get('list', [])
    if advs:
        a = advs[0]
        print(f\"OK - {a.get('advertiser_name', '?')} (status={a.get('status', '?')})\")
    else:
        print('OK but no advertiser data returned')
else:
    print(f\"FAILED - code={code}, message={msg}\")
"

    echo -n "  Reports API access: "
    TT_REPORT=$(curl -s -X GET "https://business-api.tiktok.com/open_api/v1.3/report/integrated/get/?advertiser_id=$TT_ADV&report_type=BASIC&dimensions=%5B%22stat_time_day%22%5D&metrics=%5B%22spend%22%2C%22impressions%22%5D&data_level=AUCTION_ADVERTISER&start_date=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')&end_date=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')&page_size=10" \
      -H "Access-Token: $TT_TOKEN" 2>/dev/null)
    echo "$TT_REPORT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
code = data.get('code', '?')
msg = data.get('message', '?')
if code == 0:
    rows = data.get('data', {}).get('list', [])
    if rows:
        r = rows[0].get('metrics', {})
        print(f\"OK - Yesterday: spend={r.get('spend','?')}, impressions={r.get('impressions','?')}\")
    else:
        print('OK but no data for yesterday')
else:
    print(f\"FAILED - code={code}, message={msg}\")
"
else
    echo "  No TikTok token found in Airbyte config"
fi

# Cleanup
rm -f /tmp/fb_token.txt /tmp/fb_account.txt /tmp/tt_token.txt /tmp/tt_adv.txt

echo ""
echo "=== Token tests complete ==="
