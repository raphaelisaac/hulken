#!/bin/bash
# Trigger Facebook sync via docker exec (bypassing port-forward)

echo "=== Triggering Facebook sync via k8s internal ==="
RESULT=$(sudo docker exec airbyte-abctl-control-plane curl -s -X POST \
  http://airbyte-abctl-server-svc.airbyte-abctl:8006/api/v1/connections/sync \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
  -d '{"connectionId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f"}' 2>/dev/null)
echo "$RESULT" | python3 -c '
import sys, json
data = json.load(sys.stdin)
job = data.get("job", {})
jid = job.get("id", "unknown")
status = job.get("status", "unknown")
print("Job " + str(jid) + ": " + str(status))
'

echo ""
echo "=== Checking latest jobs ==="
JOBS=$(sudo docker exec airbyte-abctl-control-plane curl -s -X POST \
  http://airbyte-abctl-server-svc.airbyte-abctl:8006/api/v1/jobs/list \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
  -d '{"configTypes":["sync"],"pagination":{"pageSize":5,"rowOffset":0}}' 2>/dev/null)
echo "$JOBS" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for j in data.get("jobs", []):
    job = j["job"]
    stats = job.get("aggregatedStats", {})
    jid = str(job.get("id", "?"))
    status = str(job.get("status", "?"))
    cid = str(job.get("configId", "?"))[:24]
    rows = str(stats.get("recordsEmitted", "?"))
    byt = str(stats.get("bytesEmitted", "?"))
    print("Job " + jid + ": " + status + " | conn=" + cid + "... | rows=" + rows + " bytes=" + byt)
'
