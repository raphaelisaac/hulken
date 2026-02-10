#!/bin/bash
# Trigger Facebook sync using ClusterIP directly

echo "=== Triggering Facebook sync ==="
sudo docker exec airbyte-abctl-control-plane python3 -c "
import urllib.request, json
url = 'http://10.96.153.33:8001/api/v1/connections/sync'
data = json.dumps({'connectionId': '5558bb48-a4ec-49ba-9e48-b9ca92f3461f'}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json', 'Authorization': 'Basic YWlyYnl0ZTpwYXNzd29yZA=='})
try:
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    job = result.get('job', {})
    print('Sync triggered: Job ' + str(job.get('id', '?')) + ' status=' + str(job.get('status', '?')))
except Exception as e:
    print('Error: ' + str(e))
" 2>/dev/null

echo ""
echo "=== Latest jobs ==="
sudo docker exec airbyte-abctl-control-plane python3 -c "
import urllib.request, json
url = 'http://10.96.153.33:8001/api/v1/jobs/list'
data = json.dumps({'configTypes': ['sync'], 'pagination': {'pageSize': 5, 'rowOffset': 0}}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json', 'Authorization': 'Basic YWlyYnl0ZTpwYXNzd29yZA=='})
try:
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    for j in result.get('jobs', []):
        job = j['job']
        stats = job.get('aggregatedStats', {})
        print('Job ' + str(job['id']) + ': ' + str(job['status']) + ' | rows=' + str(stats.get('recordsEmitted', '?')))
except Exception as e:
    print('Error: ' + str(e))
" 2>/dev/null
