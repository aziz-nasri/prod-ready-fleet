#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common/lib.sh"

LOG_FILE="/var/log/lab-bootstrap.log"

usage() {
  cat <<EOF
Usage: $0 <role>

Roles:
  proxy   - srv1: reverse proxy + NAT gateway (DMZ)
  app     - srv2: application server (app tier)
  db      - srv3: database + DNS (data tier)

Example:
  sudo $0 proxy
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage
ROLE="$1"

case "$ROLE" in
  proxy|app|db) ;;
  *) log_error "Unknown role: $ROLE"; usage ;;
esac

require_root
require_cmd nft
require_cmd systemctl

log_info "===== Starting bootstrap for role: $ROLE ====="

# --- Step 1: Baseline hardening (all roles) ---
log_info "Step 1/4: Applying baseline hardening"
"$SCRIPT_DIR/common/harden.sh"

# --- Step 2: Role-specific install ---
log_info "Step 2/4: Running role-specific install (roles/$ROLE/install.sh)"
ROLE_INSTALL="$SCRIPT_DIR/roles/${ROLE}/install.sh"
[[ -x "$ROLE_INSTALL" ]] || die "Missing or non-executable: $ROLE_INSTALL"
"$ROLE_INSTALL"

# --- Step 3: Firewall rules ---
log_info "Step 3/4: Applying firewall rules"
FIREWALL_CONFIG="$SCRIPT_DIR/firewall/firewall.conf"
[[ -f "$FIREWALL_CONFIG" ]] || die "Missing firewall config: $FIREWALL_CONFIG"
"$SCRIPT_DIR/firewall/firewall.sh"
log_info "Firewall rules applied and persisted"



# --- Step 4: post-install verification ---
log_info "Step 4/4: Running post-install smoke test"
TEST_CONFIG="$SCRIPT_DIR/test/${ROLE}.conf"
if [[ -f "$TEST_CONFIG" ]]; then
  "$SCRIPT_DIR/test/smoke-test.sh" "$HEALTH_CONFIG" > $LOG_FILE   
else
  log_warn "No ${ROLE}.conf found in the test directory for role $ROLE, skipping Smoke test."
fi
log_info "post-install smoke test finished check the log file: ${LOG_FILE}"

log_info "===== Bootstrap complete for role: $ROLE ====="
log_info "Log file: $LOG_FILE"