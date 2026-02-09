#!/bin/bash
# Check Airbyte worker logs for Facebook sync failures
set -e

echo "=== Docker containers ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -20

echo ""
echo "=== Looking for sync job logs ==="
# Airbyte stores logs in pods - find the right container
CTRL=$(sudo docker ps --format '{{.Names}}' | grep control-plane 2>/dev/null | head -1)
if [ -z "$CTRL" ]; then
    echo "Control plane container not found"
    CTRL=$(sudo docker ps --format '{{.Names}}' | head -5)
    echo "Available containers: $CTRL"
else
    echo "Control plane: $CTRL"

    echo ""
    echo "=== Recent Facebook sync logs (last 200 lines with 'facebook' or 'error') ==="
    sudo docker exec $CTRL kubectl logs -n airbyte-abctl -l app=airbyte-worker --tail=500 2>/dev/null | grep -iE "(facebook|error|fail|exception|token|expired|0 record|no record)" | tail -50 || echo "No worker logs found"

    echo ""
    echo "=== Airbyte server logs (sync-related) ==="
    sudo docker exec $CTRL kubectl logs -n airbyte-abctl -l app=airbyte-server --tail=300 2>/dev/null | grep -iE "(5558bb48|facebook|fail|error|token)" | tail -30 || echo "No server logs found"

    echo ""
    echo "=== Check for any recent pod failures ==="
    sudo docker exec $CTRL kubectl get pods -n airbyte-abctl --field-selector=status.phase!=Running 2>/dev/null | head -20 || echo "All pods running"

    echo ""
    echo "=== Pod status ==="
    sudo docker exec $CTRL kubectl get pods -n airbyte-abctl 2>/dev/null | head -20
fi

echo ""
echo "=== Done ==="
