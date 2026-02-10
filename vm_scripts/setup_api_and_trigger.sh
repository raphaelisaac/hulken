#!/bin/bash
# Re-establish API port forward and trigger Facebook sync

echo "=== Check existing port forwards ==="
ps aux | grep "port-forward" | grep -v grep

echo ""
echo "=== Setting up API port forward ==="
# Find the airbyte-server pod
SERVER_POD=$(sudo docker exec airbyte-abctl-control-plane kubectl get pods -n airbyte-abctl 2>/dev/null | grep "airbyte-abctl-server" | awk '{print $1}')
echo "Server pod: $SERVER_POD"

if [ -n "$SERVER_POD" ]; then
  # Kill old port forwards
  pkill -f "port-forward.*8006" 2>/dev/null

  # Start new port forward in background
  sudo docker exec -d airbyte-abctl-control-plane kubectl port-forward -n airbyte-abctl svc/airbyte-abctl-server-svc 8006:8006 --address=0.0.0.0 2>/dev/null
  sleep 3

  echo "=== Testing API ==="
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8006/api/v1/health 2>/dev/null)
  echo "API health check: $HTTP_CODE"

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    echo ""
    echo "=== Checking latest jobs ==="
    curl -s -X POST http://localhost:8006/api/v1/jobs/list \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
      -d '{"configTypes":["sync"],"pagination":{"pageSize":5,"rowOffset":0}}' | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for j in d.get("jobs", []):
        job = j["job"]
        stats = job.get("aggregatedStats", {})
        print(f"Job {job[\"id\"]}: {job[\"status\"]} | conn={job[\"configId\"][:24]}... | rows={stats.get(\"recordsEmitted\",\"?\")} bytes={stats.get(\"bytesEmitted\",\"?\")}")
except Exception as e:
    print(f"Error parsing jobs: {e}")
'

    echo ""
    echo "=== Triggering Facebook sync ==="
    curl -s -X POST http://localhost:8006/api/v1/connections/sync \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
      -d '{"connectionId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f"}' | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(f"Sync triggered: job={d.get(\"job\",{}).get(\"id\",\"?\")} status={d.get(\"job\",{}).get(\"status\",\"?\")}")
except Exception as e:
    print(f"Error: {e}")
'
  else
    echo "API not responding on 8006, trying alternate..."
    # Try through docker exec
    sudo docker exec airbyte-abctl-control-plane curl -s -X POST http://airbyte-abctl-server-svc.airbyte-abctl:8006/api/v1/connections/sync \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
      -d '{"connectionId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f"}' 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(f"Sync triggered via k8s: job={d.get(\"job\",{}).get(\"id\",\"?\")} status={d.get(\"job\",{}).get(\"status\",\"?\")}")
except Exception as e:
    print(f"Error: {e}")
'
  fi
else
  echo "No airbyte server pod found!"
  sudo docker exec airbyte-abctl-control-plane kubectl get pods -n airbyte-abctl 2>/dev/null
fi
