#!/bin/bash
# Add 4GB swap as safety net (even with 16GB RAM)
# Run this ON the VM after upgrade
set -e

echo "=== Adding 4GB swap ==="

# Check if swap already exists
SWAP_EXISTS=$(swapon --show | wc -l)
if [ "$SWAP_EXISTS" -gt 1 ]; then
    echo "Swap already configured:"
    swapon --show
    free -h
    echo "=== Done (swap already exists) ==="
    exit 0
fi

# Create 4GB swap file
echo "Creating 4GB swap file..."
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Set swappiness low (only use swap under pressure)
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

echo ""
echo "=== Swap configured ==="
free -h
echo ""
echo "=== Done ==="
