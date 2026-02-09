#!/bin/bash
# Check sync error details and test tokens from known locations
set -e

CLIENT_ID="a1e7af3c-c216-42ef-b5e6-0484eaafae56"
CLIENT_SECRET="u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc"
API="http://localhost:8000"

TOKEN=$(curl -s -X POST "$API/api/v1/applications/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"grant_type\":\"client_credentials\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

echo "=== Facebook source config (internal API - more detail) ==="
curl -s -X POST "$API/api/v1/sources/get" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sourceId":"47e47ea7-863f-43ba-9055-240a0b0a9a9f"}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
config = data.get('connectionConfiguration', {})
print(f\"Account IDs: {config.get('account_ids', '?')}\")
print(f\"Start date: {config.get('start_date', '?')}\")
print(f\"End date: {config.get('end_date', '?')}\")
print(f\"Insights lookback: {config.get('insights_lookback_window', '?')}\")
print(f\"Page size: {config.get('page_size', '?')}\")
print(f\"Action breakdowns: {config.get('action_breakdowns_allow_empty', '?')}\")
at = config.get('access_token', config.get('credentials', {}).get('access_token', ''))
if at and at != '**********':
    print(f'Token: {at[:20]}...{at[-10:]} (length={len(at)})')
    # Save for testing
    with open('/tmp/fb_real_token.txt', 'w') as f:
        f.write(at)
    with open('/tmp/fb_accounts.txt', 'w') as f:
        f.write(json.dumps(config.get('account_ids', [])))
else:
    print(f'Token masked or not found: {at}')
"

echo ""
echo "=== TikTok source config (internal API) ==="
curl -s -X POST "$API/api/v1/sources/get" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sourceId":"9cbb7b26-6bf9-42a1-94a3-1c643ef7fa91"}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
config = data.get('connectionConfiguration', {})
print(f\"Advertiser ID: {config.get('credentials', {}).get('advertiser_id', config.get('environment', {}).get('advertiser_id', '?'))}\")
print(f\"Start date: {config.get('start_date', '?')}\")
print(f\"End date: {config.get('end_date', '?')}\")
print(f\"Report granularity: {config.get('report_granularity', '?')}\")
at = config.get('credentials', {}).get('access_token', '')
if at and at != '**********':
    print(f'Token: {at[:20]}...{at[-10:]} (length={len(at)})')
    with open('/tmp/tt_real_token.txt', 'w') as f:
        f.write(at)
    adv = config.get('credentials', {}).get('advertiser_id', '')
    with open('/tmp/tt_adv.txt', 'w') as f:
        f.write(str(adv))
else:
    print(f'Token masked or not found')
    # Dump all keys to understand structure
    print('Config keys:', list(config.keys()))
    creds = config.get('credentials', {})
    print('Creds keys:', list(creds.keys()))
"

echo ""
echo "=== Testing Facebook token directly ==="
FB_TOKEN=$(cat /tmp/fb_real_token.txt 2>/dev/null || echo "")
if [ -n "$FB_TOKEN" ]; then
    echo -n "Token validity: "
    curl -s "https://graph.facebook.com/v21.0/me?access_token=$FB_TOKEN" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d:
    print(f\"FAILED: {d['error']['message']}\")
else:
    print(f\"VALID - ID: {d.get('id','?')}, Name: {d.get('name','?')}\")
"

    FB_ACCOUNTS=$(cat /tmp/fb_accounts.txt 2>/dev/null || echo "[]")
    python3 -c "
import json, subprocess, sys
accounts = json.loads('$FB_ACCOUNTS')
for acct in accounts:
    print(f'  Testing account act_{acct}...')
    result = subprocess.run(['curl', '-s', f'https://graph.facebook.com/v21.0/act_{acct}?fields=name,account_status,amount_spent&access_token=$FB_TOKEN'], capture_output=True, text=True)
    data = json.loads(result.stdout)
    if 'error' in data:
        print(f'    FAILED: {data[\"error\"][\"message\"]}')
    else:
        print(f'    OK: {data.get(\"name\",\"?\")} status={data.get(\"account_status\",\"?\")} spent={data.get(\"amount_spent\",\"?\")}')
    # Also test insights
    result2 = subprocess.run(['curl', '-s', f'https://graph.facebook.com/v21.0/act_{acct}/insights?date_preset=last_7d&fields=spend,impressions&access_token=$FB_TOKEN'], capture_output=True, text=True)
    data2 = json.loads(result2.stdout)
    if 'error' in data2:
        print(f'    Insights: FAILED - {data2[\"error\"][\"message\"]}')
    elif data2.get('data'):
        r = data2['data'][0]
        print(f'    Insights: OK - 7d spend={r.get(\"spend\",\"?\")}, impressions={r.get(\"impressions\",\"?\")}')
    else:
        print(f'    Insights: No data returned')
"
else
    echo "Could not extract Facebook token from internal API"
fi

echo ""
echo "=== Testing TikTok token directly ==="
TT_TOKEN=$(cat /tmp/tt_real_token.txt 2>/dev/null || echo "")
TT_ADV=$(cat /tmp/tt_adv.txt 2>/dev/null || echo "")
if [ -n "$TT_TOKEN" ] && [ -n "$TT_ADV" ]; then
    echo -n "Advertiser info: "
    curl -s -X GET "https://business-api.tiktok.com/open_api/v1.3/advertiser/info/?advertiser_ids=%5B%22$TT_ADV%22%5D" \
      -H "Access-Token: $TT_TOKEN" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('code') == 0:
    advs = d.get('data',{}).get('list',[])
    if advs:
        a = advs[0]
        print(f\"VALID - {a.get('advertiser_name','?')} (status={a.get('status','?')})\")
    else:
        print('Token valid but no advertiser returned')
else:
    print(f\"FAILED: code={d.get('code')}, msg={d.get('message','?')}\")
"
else
    echo "Could not extract TikTok token/advertiser from internal API"
fi

# Cleanup
rm -f /tmp/fb_real_token.txt /tmp/fb_accounts.txt /tmp/tt_real_token.txt /tmp/tt_adv.txt

echo ""
echo "=== Facebook last job attempt logs ==="
curl -s -X POST "$API/api/v1/jobs/get" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":112}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
job = data.get('job', {})
print(f\"Job 112 status: {job.get('status')}\")
print(f\"Config type: {job.get('configType')}\")
attempts = data.get('attempts', [])
print(f\"Attempts: {len(attempts)}\")
for i, a in enumerate(attempts):
    att = a.get('attempt', {})
    print(f\"  Attempt {i}: status={att.get('status')}, records={att.get('recordsSynced', att.get('totalStats', {}).get('recordsEmitted', '?'))}\")
    out = att.get('output', {})
    if out:
        sync = out.get('sync', out.get('discover_catalog', {}))
        if isinstance(sync, dict):
            summary = sync.get('standardSyncSummary', {})
            print(f\"    Records: {summary.get('recordsSynced', '?')}, Status: {summary.get('status', '?')}\")
            per_stream = sync.get('streamStats', [])
            if per_stream:
                print('    Per stream:')
                for s in per_stream[:10]:
                    sname = s.get('streamName', '?')
                    stats = s.get('stats', {})
                    print(f\"      {sname}: emitted={stats.get('recordsEmitted',0)}, committed={stats.get('recordsCommitted',0)}\")
    fail = att.get('failureSummary', a.get('failureSummary', {}))
    if fail and fail.get('failures'):
        for f in fail['failures'][:3]:
            print(f\"    FAILURE: {f.get('failureType','?')}: {str(f.get('externalMessage', f.get('internalMessage', '?')))[:300]}\")
" 2>/dev/null || echo "Could not get job details"

echo ""
echo "=== Done ==="
