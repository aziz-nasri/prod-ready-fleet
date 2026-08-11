#!/usr/bin/env bash

set -euo pipefail
source health.conf

echo -e "Data tier reachability:\n"
nc -zv $DATA_IP $DATA_PORT &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "OK: Database server is reachable through port ${DATA_PORT}"
else
    echo "ERROR: Database server is not reachable through port ${DATA_PORT}."
fi
nc -zv $DNS_IP $DNS_PORT &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "OK: DNS is reachable through port ${DNS_PORT}."
else
    echo "ERROR: DNS is not reachable through port ${DNS_PORT}."
fi

# Get values
current=$(systemctl show -p MemoryCurrent --value "$SERVICE")
max=$(systemctl show -p MemoryMax --value "$SERVICE")
# Handle unlimited (infinity)
if [[ "$max" == "infinity" || "$max" -eq 0 ]]; then
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