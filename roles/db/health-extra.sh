#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/health.conf"

echo "Check Database accepts connections:"
pg_isready -h $DATA_IP &> /dev/null
if [[ $? == 0 ]]; then
    echo "OK: Database accepts connections."
else
    echo "ERROR: Database does not accepts connections."
fi
echo ""

echo "Checking DNS resolves internal names correctly:"
dig @localhost $APP_DOMAIN +short &> /dev/null
if [[ $? == 0 ]]; then
    echo "OK: DNS resolves internal names correctly."
else
    echo "ERROR: DNS cannot resolve internal names correctly."
fi
echo ""

echo "Checking DNS forwarding:"
if dig +time=2 +tries=1 +short example.com >/dev/null 2>&1; then
  echo "OK: External resolution succeeded."
else
  echo "ERROR: External resolution failed, forwarding appears disabled"
fi
echo ""

echo "Last backup age:"
NEWEST_FILE=$(find "$BACKUP_DIR" -mindepth 1 \( -type f -o -type d \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
if [[ -z "$NEWEST_FILE" ]]; then
  echo "ERROR: No backup files found"
fi
# Check if file is older than MAX_AGE_DAYS
if [[ $(find "$NEWEST_FILE" -mmin +$((MAX_AGE_DAYS * 1440)) &> /dev/null) ]]; then
  echo "ERROR: Backup is older than ${MAX_AGE_DAYS}days: $NEWEST_FILE"
else
  echo "OK: Backup is recent: $NEWEST_FILE"
fi

echo -e "\n======================================================"
echo "==================LOGS AND ERORRS===================="
echo -e "======================================================\n"
# postgresql recent logs
echo "Recent postgresql service logs:"
echo "--------------------------------------------------------------"
sudo journalctl -u postgresql | head -n 30
echo -e "--------------------------------------------------------------\n"
# dnsmasq recent logs
echo "Recent dnsmasq service logs:"
echo "--------------------------------------------------------------"
sudo journalctl -u dnsmasq | head -n 30
echo -e "--------------------------------------------------------------\n"