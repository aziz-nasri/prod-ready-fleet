#!/usr/bin/env bash

set -euo pipefail
source ./health.conf

echo "Data tier reachability:"
if timeout 3 bash -c "</dev/tcp/$DATA_IP/$DATA_PORT" &>/dev/null; then
    echo "OK: Database server is reachable through port ${DATA_PORT}"
else
     echo "ERROR: Database server is not reachable through port ${DATA_PORT}."
fi

if timeout 3 bash -c "</dev/tcp/$DNS_IP/$DNS_PORT" &>/dev/null; then
    echo "OK: DNS is reachable through port ${DNS_PORT}."
else
    echo "ERROR: DNS is not reachable through port ${DNS_PORT}."
fi
echo ""

# Get values
current=$(systemctl show -p MemoryCurrent --value "$SERVICE")
max=$(systemctl show -p MemoryMax --value "$SERVICE")
# Handle unlimited (infinity)
if [[ "$max" == "infinity" || "$max" == 0 ]]; then
    echo "No MemoryMax limit set"
fi
# Calculate percentage
percent=$(( current * 100 / max ))
echo "Memory usage: $percent% ($current / $max bytes)"
if (( percent >= THRESHOLD )); then
    echo "WARNING: $SERVICE is at ${percent}% of MemoryMax!"
else
    echo "OK: ${SERVICE} Memory usage is under the Threshold."
fi

echo -e "\n======================================================"
echo "==================LOGS AND ERORRS===================="
echo -e "======================================================\n"
# app.service recent logs
echo "Recent myapp service logs:"
echo "--------------------------------------------------------------"
sudo journalctl -u $SERVICE | head -n 30
echo -e "--------------------------------------------------------------\n"