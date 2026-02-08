#!/bin/bash
# Network Watchdog - runs every minute via systemd timer
# First tries to restart networking, then reboots if that fails
LOG=/var/log/network_watchdog.log

check_network() {
    ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1 && return 0
    ping -c 1 -W 3 169.254.169.254 > /dev/null 2>&1 && return 0
    curl -sf --max-time 5 http://169.254.169.254/computeMetadata/v1/ -H 'Metadata-Flavor: Google' > /dev/null 2>&1 && return 0
    return 1
}

if check_network; then
    exit 0
fi

echo "$(date): Network check FAILED - attempting repair" >> $LOG

# Step 1: Try restarting the network interface
echo "$(date): Restarting ens4..." >> $LOG
ip link set ens4 down 2>/dev/null
sleep 2
ip link set ens4 up 2>/dev/null
sleep 5

if check_network; then
    echo "$(date): Network restored via interface restart" >> $LOG
    exit 0
fi

# Step 2: Try restarting systemd-networkd
echo "$(date): Restarting systemd-networkd..." >> $LOG
systemctl restart systemd-networkd
sleep 10

if check_network; then
    echo "$(date): Network restored via systemd-networkd restart" >> $LOG
    exit 0
fi

# Step 3: Full reboot as last resort
echo "$(date): All network recovery failed - REBOOTING" >> $LOG
/sbin/reboot
