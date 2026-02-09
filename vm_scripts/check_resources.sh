#!/bin/bash
echo "=== VM Memory ==="
free -h

echo ""
echo "=== VM Disk ==="
df -h /

echo ""
echo "=== Docker disk usage ==="
sudo docker system df 2>/dev/null

echo ""
echo "=== Top memory consumers ==="
ps aux --sort=-%mem | head -15

echo ""
echo "=== Kubernetes resource usage ==="
CTRL="airbyte-abctl-control-plane"
sudo docker exec $CTRL kubectl top pods -n airbyte-abctl 2>/dev/null || echo "Metrics server not available"

echo ""
echo "=== Kubernetes resource limits ==="
sudo docker exec $CTRL kubectl describe pods -n airbyte-abctl airbyte-abctl-worker-766b6b99dc-cxrs5 2>/dev/null | grep -A5 "Limits\|Requests\|OOMKilled\|Restart Count\|Last State" | head -30 || echo "Cannot describe pod"

echo ""
echo "=== Recent OOM kills in dmesg ==="
sudo dmesg | grep -i "oom\|killed process\|out of memory" | tail -10 2>/dev/null || echo "No OOM kills found"

echo ""
echo "=== Docker container stats (snapshot) ==="
sudo docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}" 2>/dev/null | head -5

echo ""
echo "=== Done ==="
