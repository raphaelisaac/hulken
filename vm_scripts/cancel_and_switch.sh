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
print('Token OK')

# Cancel job 125
print('')
print('=== Cancelling job 125 ===')
cancel_url = '$API/jobs/cancel'
cancel_data = json.dumps({'id': 125}).encode()
cancel_req = urllib.request.Request(cancel_url, data=cancel_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
try:
    cancel_resp = urllib.request.urlopen(cancel_req)
    result = json.loads(cancel_resp.read())
    job = result.get('job', {})
    print('Job 125: ' + str(job.get('status', '?')))
except Exception as e:
    print('Cancel error: ' + str(e))

# Get Facebook connection config
print('')
print('=== Getting Facebook connection config ===')
conn_url = '$API/connections/get'
conn_data = json.dumps({'connectionId': '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'}).encode()
conn_req = urllib.request.Request(conn_url, data=conn_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
conn_resp = urllib.request.urlopen(conn_req)
conn = json.loads(conn_resp.read())

# Show current sync modes
for stream in conn.get('syncCatalog', {}).get('streams', []):
    cfg = stream.get('config', {})
    s = stream.get('stream', {})
    name = s.get('name', '?')
    mode = cfg.get('syncMode', '?')
    dest = cfg.get('destinationSyncMode', '?')
    print('  ' + name + ': ' + mode + ' / ' + dest)
" 2>/dev/null
