#!/bin/bash
echo "=== CONNECTOR PODS ==="
sudo kubectl get pods -n airbyte-abctl 2>/dev/null | grep -v Completed | head -20 || echo "kubectl not found"

echo ""
echo "=== RUNNING CONNECTOR LOGS (last 20 lines) ==="
# Find the running source/destination pod
POD=$(sudo kubectl get pods -n airbyte-abctl 2>/dev/null | grep -E "source|replication" | grep Running | head -1 | awk '{print $1}')
if [ -n "$POD" ]; then
  echo "Pod: $POD"
  sudo kubectl logs "$POD" -n airbyte-abctl --tail=20 2>/dev/null
else
  echo "No active connector pod found"
  echo "All pods:"
  sudo kubectl get pods -n airbyte-abctl 2>/dev/null | tail -20
fi

echo ""
echo "=== MEMORY CHECK ==="
free -h | head -2
