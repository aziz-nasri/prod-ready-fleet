#!/usr/bin/env bash

set -euo pipefail

# system update
sudo apt update &> /dev/null
sudo apt upgrade &> /dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: System updated successfuly" | tee -a "${LOG_FILE:-/var/log/lab-bootstrap.log}"


