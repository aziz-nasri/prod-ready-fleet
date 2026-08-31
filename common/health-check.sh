#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../roles/proxy/health.conf"

echo "======================================================"
echo "==================SYSTEM STATUS===================="
echo -e "======================================================\n"
echo "Hostname: $(hostname)"
echo "Kernel version: $(hostnamectl | grep Kernel | cut -d":" -f2)"
echo "Current Date: $(date)"
echo "Uptime: $(uptime | cut -d"," -f1,2)"
echo "Number of running processes: $(ps -e --no-headers | wc -l)"

echo "======================================================"
echo "==================SYSTEM RESOURCES===================="
echo -e "======================================================\n"
echo "Load average: $(uptime | cut -d"," -f3)"
echo "CPU usage:"
echo "--------------------------------------------------------------"
CPU=$(sar -u 1 7)
IDL_CPU=$(echo "$CPU" | grep -i "average" | awk '{print $8}')
echo "$CPU"
if [[ $IDL_CPU < $CPU_THRES ]]; then
    echo "WARNING: CPU usage is almost full!"
else
    echo "OK: CPU usage is good."
fi
echo -e "--------------------------------------------------------------\n"
echo "Memory usage:"
echo "--------------------------------------------------------------"
free -h | awk 'NR <= 2'
AVAILABLE=$(free -m | awk '/Mem:/ {print $7}')
if [[ $AVAILABLE < $MEM_THRES ]]; then
    echo "WARNING: Available memory is low, ${AVAILABLE} MB."
else
    echo "OK: Sufficient memory available"
fi
echo -e "--------------------------------------------------------------\n"
echo "Swap usage:"
echo "--------------------------------------------------------------"
free -h | awk 'NR==1 || NR==3'
echo -e "--------------------------------------------------------------\n"
DISK_USG=$(df -h / | awk 'NR==2 {print $5}')
echo "Disk usage: ${DISK_USG}"
if [[ $(echo "$DISK_USG" | tr -d '%') > $DISK_THRES ]]; then
    echo "WARNING: Available Disk is low, ${DISK_USG}."
else
    echo "OK: Sufficient Disk available"
fi
echo "--------------------------------------------------------------"
df -h
echo -e "--------------------------------------------------------------\n"
echo "Inode usage:"
echo "--------------------------------------------------------------"
df -hi
echo -e "--------------------------------------------------------------\n"
echo "Disk I/O:"
echo "--------------------------------------------------------------"
iostat -dh
echo -e "--------------------------------------------------------------\n"

echo "======================================================"
echo "==================SERVICES AND PROCESSES===================="
echo -e "======================================================\n"
echo "Critical services status:"
echo "--------------------------------------------------------------"
for service in "${SERVICES[@]}"; do
    echo "=== $service ==="
    sudo systemctl is-active "$service"
    sudo systemctl is-enabled "$service"
    echo
done
echo -e "--------------------------------------------------------------\n"
echo "Zombie processes:"
echo "--------------------------------------------------------------"
ps aux | awk '$8=="Z" || $8=="Z+"'
echo -e "--------------------------------------------------------------\n"
echo "Top 5 CPU consuming processes:"
echo "--------------------------------------------------------------"
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 6
echo -e "--------------------------------------------------------------\n"

echo "======================================================"
echo "==================NETWORK AND REACHABILITY===================="
echo -e "======================================================\n"
echo "Interfaces:"
echo "--------------------------------------------------------------"
ip -br link show
echo -e "--------------------------------------------------------------\n"
echo "IP addresses:"
echo "--------------------------------------------------------------"
ip -br addr show
echo -e "--------------------------------------------------------------\n"
echo "The listeing ports:"
echo "--------------------------------------------------------------"
sudo ss -ltun
echo -e "--------------------------------------------------------------\n"
echo "Firewall ruleset:"
echo "--------------------------------------------------------------"
if ! command -v nft &>/dev/null; then
  echo "ERROR: nftables is not installed (nft command not found)."
else
  sudo nft list ruleset
fi
echo -e "--------------------------------------------------------------\n"

# runnig server specific health check
"$(dirname "$0")/../roles/proxy/health-extra.sh"

echo -e "\nRecent errors."
echo "--------------------------------------------------------------"
sudo journalctl -p err | head -n 30
echo -e "--------------------------------------------------------------\n"
