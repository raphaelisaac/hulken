#!/bin/bash
# Trigger Facebook sync
echo "=== Triggering Facebook sync ==="
curl -s -X POST http://localhost:8006/api/v1/connections/sync \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
  -d '{"connectionId":"5558bb48-a4ec-49ba-9e48-b9ca92f3461f"}' | python3 -m json.tool

echo ""
echo "=== Current jobs ==="
curl -s -X POST http://localhost:8006/api/v1/jobs/list \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
  -d '{"configTypes":["sync"],"pagination":{"pageSize":3,"rowOffset":0}}' | python3 -c '
import sys, json
d = json.load(sys.stdin)
for j in d.get("jobs", []):
    job = j["job"]
    stats = job.get("aggregatedStats", {})
    print(f"Job {job[\"id\"]}: {job[\"status\"]} | conn={job[\"configId\"][:24]}... | rows={stats.get(\"recordsEmitted\",\"?\")} bytes={stats.get(\"bytesEmitted\",\"?\")}")
'
