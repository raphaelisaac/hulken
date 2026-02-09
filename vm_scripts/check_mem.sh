#!/bin/bash
echo "=== MEMORY ==="
free -h
echo ""
echo "=== OOM KILLS ==="
sudo dmesg 2>/dev/null | grep -i "killed process" | tail -5 || echo "none"
echo ""
echo "=== JAVA PROCESSES (connectors) ==="
ps aux | grep java | grep -v grep | head -5 || echo "no java"
echo ""
echo "=== TOP MEMORY CONSUMERS ==="
ps aux --sort=-%mem | head -8
