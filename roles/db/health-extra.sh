#!/usr/bin/env bash

set -euo pipefail

echo "Check Database accepts connections:"
pg_isready -h $DATA_IP &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "OK: Database accepts connections."
else
    echo "ERROR: Database does not accepts connections."
fi 

echo "Check Database accepts app role connection:"
psql -U appuser -d appdb -c 'SELECT 1' &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "OK: Database accepts app role connections and credential path works."
else
    echo "ERROR: Database does not accepts app role connections or credential path isn't working."
fi

echo "Checking DNS resolves internal names correctly:"
dig @localhost $APP_DOMAIN +short &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "OK: DNS resolves internal names correctly."
else
    echo "ERROR: DNS cannot resolve internal names correctly."
fi 

echo "Checking DNS forwarding is still disabled:"
if dig +time=2 +tries=1 +short example.com >/dev/null 2>&1; then
  echo "ERROR: External resolution succeeded, forwarding (or recursion) is working"
else
  echo "OK: External resolution failed, forwarding appears disabled"
fi

echo -e "Last backup age:"
NEWEST=$(find "$BACKUP_DIR" -mindepth 1 \( -type f -o -type d \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
if [[ -z "$NEWEST_FILE" ]]; then
  echo "ERROR: No backup files found"
fi
# Check if file is older than MAX_AGE_DAYS
if [[ $(find "$NEWEST_FILE" -mmin +$((MAX_AGE_DAYS * 1440)) ) ]]; then
  echo "ERROR: Backup is older than ${MAX_AGE_DAYS}days: $NEWEST_FILE"
else
  echo "OK: Backup is recent: $NEWEST_FILE"
fi