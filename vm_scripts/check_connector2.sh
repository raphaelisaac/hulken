#!/bin/bash
echo "=== DOCKER CONTAINERS ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null | head -15

echo ""
echo "=== KUBECTL WITH KUBECONFIG ==="
export KUBECONFIG=$HOME/.airbyte/abctl/abctl.kubeconfig
kubectl get pods -A 2>/dev/null | grep -v Completed | head -30 || echo "trying alternate..."

echo ""
echo "=== ABCTL STATUS ==="
abctl local status 2>/dev/null || echo "abctl not in PATH"

echo ""
echo "=== CHECK DOCKER EXEC FOR PODS ==="
sudo docker exec airbyte-abctl-control-plane kubectl get pods -A 2>/dev/null | grep -v Completed | head -30
