#!/bin/bash
# Install network watchdog on the VM
set -e

# Create the watchdog script
cp /tmp/network_watchdog.sh /home/Jarvis/network_watchdog.sh
chmod +x /home/Jarvis/network_watchdog.sh

# Create systemd service
cat > /etc/systemd/system/network-watchdog.service << 'EOF'
[Unit]
Description=Network Watchdog - detects and recovers from network failures

[Service]
Type=oneshot
ExecStart=/home/Jarvis/network_watchdog.sh
EOF

# Create systemd timer (every 1 minute)
cat > /etc/systemd/system/network-watchdog.timer << 'EOF'
[Unit]
Description=Run network watchdog every minute

[Timer]
OnBootSec=120
OnUnitActiveSec=60
AccuracySec=10

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable network-watchdog.timer
systemctl start network-watchdog.timer

echo "WATCHDOG INSTALLED SUCCESSFULLY"
systemctl status network-watchdog.timer --no-pager
