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

# List all recent jobs
list_url = '$API/jobs/list'
list_data = json.dumps({'configTypes': ['sync'], 'pagination': {'pageSize': 10, 'rowOffset': 0}}).encode()
list_req = urllib.request.Request(list_url, data=list_data, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
list_resp = urllib.request.urlopen(list_req)
jobs_data = json.loads(list_resp.read())
for j in jobs_data.get('jobs', []):
    job = j['job']
    stats = job.get('aggregatedStats', {})
    attempts = j.get('attempts', [])
    last_attempt = attempts[-1] if attempts else {}
    attempt_stats = last_attempt.get('attempt', {}).get('totalStats', {})
    created = str(job.get('createdAt', 0))
    updated = str(job.get('updatedAt', 0))
    print('Job ' + str(job['id']) + ': ' + str(job['status']) +
          ' | conn=' + str(job['configId'])[:12] + '...' +
          ' | rows=' + str(stats.get('recordsEmitted', '?')) +
          ' | bytes=' + str(stats.get('bytesEmitted', '?')) +
          ' | created=' + created +
          ' | updated=' + updated)
" 2>/dev/null
