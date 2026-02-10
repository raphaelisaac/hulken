#!/bin/bash
# Check latest sync jobs
curl -s -X POST http://localhost:8006/api/v1/jobs/list \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic YWlyYnl0ZTpwYXNzd29yZA==' \
  -d '{"configTypes":["sync"],"pagination":{"pageSize":5,"rowOffset":0}}' | python3 -c '
import sys, json
d = json.load(sys.stdin)
for j in d.get("jobs", []):
    job = j["job"]
    stats = j.get("job", {}).get("aggregatedStats", {})
    jid = job["id"]
    status = job["status"]
    cid = job["configId"][:24]
    rows = stats.get("recordsEmitted", "?")
    byt = stats.get("bytesEmitted", "?")
    print(f"Job {jid}: {status} | conn={cid}... | rows={rows} bytes={byt}")
'
