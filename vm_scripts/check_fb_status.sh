#!/bin/bash
# Check Facebook sync job 125 status via ClusterIP
API="http://10.96.153.33:8001/api/v1"

sudo docker exec airbyte-abctl-control-plane python3 -c "
import urllib.request, json

url = '$API/applications/token'
data = json.dumps({
    'client_id': 'a1e7af3c-c216-42ef-b5e6-0484eaafae56',
    'client_secret': 'u3Kr5pJRLp0QBJFdlL9oOLIKKU6U9XPc',
    'grant_type': 'client_credentials'
}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
resp = urllib.request.urlopen(req)
token = json.loads(resp.read()).get('access_token', '')

# Get job 125 details
url2 = '$API/jobs/get'
data2 = json.dumps({'id': 125}).encode()
req2 = urllib.request.Request(url2, data=data2, headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
})
resp2 = urllib.request.urlopen(req2)
result = json.loads(resp2.read())
job = result.get('job', {})
stats = job.get('aggregatedStats', {})
print('Job 125 (Facebook):')
print('  Status: ' + str(job.get('status', '?')))
print('  Rows: ' + str(stats.get('recordsEmitted', '?')))
print('  Bytes: ' + str(stats.get('bytesEmitted', '?')))

attempts = result.get('attempts', [])
if attempts:
    last = attempts[-1].get('attempt', {})
    print('  Last attempt status: ' + str(last.get('status', '?')))
    tstats = last.get('totalStats', {})
    print('  Records committed: ' + str(tstats.get('recordsCommitted', '?')))
" 2>/dev/null
