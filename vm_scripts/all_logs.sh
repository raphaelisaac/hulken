#!/bin/bash
echo "=== ALL CONTAINERS IN JOB 125 ==="
sudo docker exec airbyte-abctl-control-plane kubectl get pod replication-job-125-attempt-0 -n airbyte-abctl -o jsonpath='{.spec.containers[*].name}' 2>/dev/null
echo ""

for c in source destination orchestrator; do
  echo ""
  echo "=== $c (last 15 lines) ==="
  sudo docker exec airbyte-abctl-control-plane kubectl logs replication-job-125-attempt-0 -n airbyte-abctl -c $c --tail=15 2>&1 | head -20
done
