#!/bin/bash
echo "=== REPLICATION JOB 125 LOGS (source container, last 30 lines) ==="
sudo docker exec airbyte-abctl-control-plane kubectl logs replication-job-125-attempt-0 -n airbyte-abctl -c source --tail=30 2>/dev/null

echo ""
echo "=== DESTINATION CONTAINER LOGS (last 15 lines) ==="
sudo docker exec airbyte-abctl-control-plane kubectl logs replication-job-125-attempt-0 -n airbyte-abctl -c destination --tail=15 2>/dev/null
