#!/bin/bash
# Trigger Facebook sync via docker exec with correct service name

API="http://airbyte-abctl-airbyte-server-svc.airbyte-abctl:8001/api/v1"
AUTH="Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA=="

echo "=== Test API ==="
sudo docker exec airbyte-abctl-control-plane wget -q -O - "$API/health" 2>/dev/null || \
sudo docker exec airbyte-abctl-control-plane curl -s "$API/health" 2>/dev/null || \
echo "Neither wget nor curl found, trying with python..."

echo ""
echo "=== Triggering Facebook sync ==="
sudo docker exec airbyte-abctl-control-plane python3 -c "
import urllib.request, json
url = '$API/connections/sync'
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
url = '$API/jobs/list'
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
