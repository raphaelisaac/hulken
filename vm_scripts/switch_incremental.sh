#!/bin/bash
API="http://10.96.153.33:8001/api/v1"

sudo docker exec airbyte-abctl-control-plane python3 -c "
import urllib.request, json

# Get token
url = '$API/applications/token'
data = json.dumps({
    'client_id': 'a1e7af3c-c216-42ef-b5e6-0484eaafae56',
    'client_secret': 'u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc',
    'grant_type': 'client_credentials'
}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req)
token = json.loads(resp.read()).get('access_token', '')

# Streams that support incremental (have date cursor)
INCREMENTAL_STREAMS = [
    'ads_insights', 'ads_insights_age_and_gender', 'ads_insights_country',
    'ads_insights_region', 'ads_insights_dma', 'ads_insights_platform_and_device',
    'ads_insights_action_type', 'activities'
]

# Metadata streams - keep full_refresh but switch to overwrite (they're small)
FULL_REFRESH_STREAMS = [
    'campaigns', 'ad_sets', 'ads', 'ad_creatives', 'custom_conversions', 'images'
]

# ===== FACEBOOK =====
print('=== Updating Facebook connection ===')
conn_url = '$API/connections/get'
conn_data = json.dumps({'connectionId': '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'}).encode()
conn_req = urllib.request.Request(conn_url, data=conn_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
conn_resp = urllib.request.urlopen(conn_req)
conn = json.loads(conn_resp.read())

# Update sync modes
for stream in conn.get('syncCatalog', {}).get('streams', []):
    s = stream.get('stream', {})
    cfg = stream.get('config', {})
    name = s.get('name', '?')

    supported = s.get('supportedSyncModes', [])

    if name in INCREMENTAL_STREAMS and 'incremental' in supported:
        cfg['syncMode'] = 'incremental'
        cfg['destinationSyncMode'] = 'append'
        cfg['cursorField'] = ['date_start']
        print('  ' + name + ' -> incremental/append')
    elif name in FULL_REFRESH_STREAMS:
        cfg['syncMode'] = 'full_refresh'
        cfg['destinationSyncMode'] = 'overwrite'
        print('  ' + name + ' -> full_refresh/overwrite (metadata, small)')
    else:
        print('  ' + name + ' -> keeping ' + cfg.get('syncMode', '?') + '/' + cfg.get('destinationSyncMode', '?'))

# Save updated connection
update_url = '$API/connections/update'
update_payload = {
    'connectionId': conn['connectionId'],
    'syncCatalog': conn['syncCatalog']
}
update_data = json.dumps(update_payload).encode()
update_req = urllib.request.Request(update_url, data=update_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
}, method='POST')
try:
    update_resp = urllib.request.urlopen(update_req)
    print('Facebook connection updated OK')
except Exception as e:
    print('Facebook update error: ' + str(e))

# ===== TIKTOK =====
print('')
print('=== Getting TikTok connection config ===')
tt_url = '$API/connections/get'
tt_data = json.dumps({'connectionId': '292df228-3e1b-4dc2-879e-bd78cc15bcf8'}).encode()
tt_req = urllib.request.Request(tt_url, data=tt_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
tt_resp = urllib.request.urlopen(tt_req)
tt_conn = json.loads(tt_resp.read())

TT_INCREMENTAL = ['ads_reports_daily', 'ad_groups_reports_daily', 'campaigns_reports_daily', 'advertisers_reports_daily']
TT_FULL_REFRESH = ['ads', 'ad_groups', 'campaigns']

for stream in tt_conn.get('syncCatalog', {}).get('streams', []):
    s = stream.get('stream', {})
    cfg = stream.get('config', {})
    name = s.get('name', '?')
    supported = s.get('supportedSyncModes', [])

    if name in TT_INCREMENTAL and 'incremental' in supported:
        cfg['syncMode'] = 'incremental'
        cfg['destinationSyncMode'] = 'append'
        print('  ' + name + ' -> incremental/append')
    elif name in TT_FULL_REFRESH:
        cfg['syncMode'] = 'full_refresh'
        cfg['destinationSyncMode'] = 'overwrite'
        print('  ' + name + ' -> full_refresh/overwrite (metadata)')
    else:
        current = cfg.get('syncMode', '?') + '/' + cfg.get('destinationSyncMode', '?')
        if 'incremental' in supported and cfg.get('syncMode') == 'full_refresh':
            cfg['syncMode'] = 'incremental'
            cfg['destinationSyncMode'] = 'append'
            print('  ' + name + ' -> incremental/append (auto-detected)')
        else:
            print('  ' + name + ' -> keeping ' + current)

tt_update = {
    'connectionId': tt_conn['connectionId'],
    'syncCatalog': tt_conn['syncCatalog']
}
tt_update_data = json.dumps(tt_update).encode()
tt_update_req = urllib.request.Request(update_url, data=tt_update_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
}, method='POST')
try:
    tt_update_resp = urllib.request.urlopen(tt_update_req)
    print('TikTok connection updated OK')
except Exception as e:
    print('TikTok update error: ' + str(e))

# ===== SHOPIFY =====
print('')
print('=== Getting Shopify connection config ===')
sh_url = '$API/connections/get'
sh_data = json.dumps({'connectionId': 'c79a5968-f31b-44b9-b9e6-fa79e630fa40'}).encode()
sh_req = urllib.request.Request(sh_url, data=sh_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
sh_resp = urllib.request.urlopen(sh_req)
sh_conn = json.loads(sh_resp.read())

for stream in sh_conn.get('syncCatalog', {}).get('streams', []):
    s = stream.get('stream', {})
    cfg = stream.get('config', {})
    name = s.get('name', '?')
    supported = s.get('supportedSyncModes', [])
    current = cfg.get('syncMode', '?') + '/' + cfg.get('destinationSyncMode', '?')

    if 'incremental' in supported and cfg.get('syncMode') == 'full_refresh':
        cfg['syncMode'] = 'incremental'
        cfg['destinationSyncMode'] = 'append'
        print('  ' + name + ' -> incremental/append')
    else:
        print('  ' + name + ' -> keeping ' + current)

sh_update = {
    'connectionId': sh_conn['connectionId'],
    'syncCatalog': sh_conn['syncCatalog']
}
sh_update_data = json.dumps(sh_update).encode()
sh_update_req = urllib.request.Request(update_url, data=sh_update_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
}, method='POST')
try:
    sh_update_resp = urllib.request.urlopen(sh_update_req)
    print('Shopify connection updated OK')
except Exception as e:
    print('Shopify update error: ' + str(e))

print('')
print('=== Done. Triggering Facebook sync ===')
sync_url = '$API/connections/sync'
sync_data = json.dumps({'connectionId': '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'}).encode()
sync_req = urllib.request.Request(sync_url, data=sync_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
try:
    sync_resp = urllib.request.urlopen(sync_req)
    result = json.loads(sync_resp.read())
    job = result.get('job', {})
    print('Facebook sync started: Job ' + str(job.get('id', '?')) + ' status=' + str(job.get('status', '?')))
except Exception as e:
    print('Sync trigger error: ' + str(e))
" 2>/dev/null
