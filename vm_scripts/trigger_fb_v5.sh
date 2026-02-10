#!/bin/bash
# Trigger Facebook sync using OAuth token auth

API="http://10.96.153.33:8001/api/v1"

echo "=== Getting OAuth token ==="
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
try:
    resp = urllib.request.urlopen(req)
    token_data = json.loads(resp.read())
    token = token_data.get('access_token', '')
    print('Token obtained: ' + token[:20] + '...')

    # Trigger Facebook sync
    print('')
    print('=== Triggering Facebook sync ===')
    sync_url = '$API/connections/sync'
    sync_data = json.dumps({'connectionId': '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'}).encode()
    sync_req = urllib.request.Request(sync_url, data=sync_data, headers={
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token
    })
    sync_resp = urllib.request.urlopen(sync_req)
    result = json.loads(sync_resp.read())
    job = result.get('job', {})
    print('Sync triggered: Job ' + str(job.get('id', '?')) + ' status=' + str(job.get('status', '?')))

    # List jobs
    print('')
    print('=== Latest jobs ===')
    list_url = '$API/jobs/list'
    list_data = json.dumps({'configTypes': ['sync'], 'pagination': {'pageSize': 5, 'rowOffset': 0}}).encode()
    list_req = urllib.request.Request(list_url, data=list_data, headers={
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token
    })
    list_resp = urllib.request.urlopen(list_req)
    jobs_data = json.loads(list_resp.read())
    for j in jobs_data.get('jobs', []):
        job = j['job']
        stats = job.get('aggregatedStats', {})
        print('Job ' + str(job['id']) + ': ' + str(job['status']) + ' | conn=' + str(job['configId'])[:24] + '... | rows=' + str(stats.get('recordsEmitted', '?')))
except Exception as e:
    print('Error: ' + str(e))
" 2>/dev/null
