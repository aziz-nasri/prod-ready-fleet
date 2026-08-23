#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/lib.sh"

usage() {
  echo "Usage: $0 <role>"
  echo "Roles: proxy | app | db"
  exit 1
}

[[ $# -eq 1 ]] || usage
ROLE="$1"

CONFIG_FILE="$SCRIPT_DIR/${ROLE}.conf"
[[ -f "$CONFIG_FILE" ]] || die "Missing test config: $CONFIG_FILE"
source "$CONFIG_FILE"

PASS=0
FAIL=0
LAYER_FAILED=0

check() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    echo "  [PASS] $desc"
    ((PASS++))
  else
    echo "  [FAIL] $desc"
    ((FAIL++))
    LAYER_FAILED=1
  fi
}

check_negative() {
  # Passes if the command FAIL
  local desc="$1"; shift
  if ! "$@" &>/dev/null; then
    echo "  [PASS] $desc (correctly blocked)"
    ((PASS++))
  else
    echo "  [FAIL] $desc (should have been blocked, but succeeded)"
    ((FAIL++))
    LAYER_FAILED=1
  fi
}

stop_if_layer_failed() {
  local layer_name="$1"
  if [[ $LAYER_FAILED -eq 1 ]]; then
    echo ""
    echo "=== STOPPED: Layer '$layer_name' failed. Fix issues here before testing higher layers. ==="
    echo "Summary: $PASS passed, $FAIL failed"
    exit 1
  fi
  LAYER_FAILED=0
}

echo "===== Smoke test: $ROLE ====="

#Layer 1: Network connectivity
echo ""
echo "--- Layer 1: Network ---"
for target in "${PING_TARGETS[@]}"; do
  check "Can reach $target" ping -c2 -W2 "$target"
done
for target in "${PING_SHOULD_FAIL[@]:-}"; do
  [[ -n "$target" ]] && check_negative "Cannot reach $target (different zone)" ping -c2 -W2 "$target"
done
stop_if_layer_failed "Network"

# --- Layer 2: Firewall enforcement (positive + negative) ---
echo ""
echo "--- Layer 2: Firewall ---"
for entry in "${ALLOWED_CONNECTIONS[@]:-}"; do
  [[ -z "$entry" ]] && continue
  IFS='|' read -r host port desc <<< "$entry"
  check "Allowed: $desc" nc -zv -w3 "$host" "$port"
done
for entry in "${DENIED_CONNECTIONS[@]:-}"; do
  [[ -z "$entry" ]] && continue
  IFS='|' read -r host port desc <<< "$entry"
  check_negative "Denied: $desc" nc -zv -w3 "$host" "$port"
done
stop_if_layer_failed "Firewall"

# --- Layer 3: Services ---
echo ""
echo "--- Layer 3: Services ---"
for svc in "${SERVICES[@]}"; do
  check "$svc is active" systemctl is-active --quiet "$svc"
  check "$svc is enabled" systemctl is-enabled --quiet "$svc"
done
for entry in "${PORTS_LISTENING[@]:-}"; do
  [[ -z "$entry" ]] && continue
  IFS='|' read -r port desc <<< "$entry"
  check "Port $port listening ($desc)" bash -c "ss -tln | grep -q ':$port '"
done
stop_if_layer_failed "Services"

# --- Layer 4: Role-specific checks ---
echo ""
echo "--- Layer 4: Role-specific ---"
if declare -f role_specific_checks &>/dev/null; then
  role_specific_checks
else
  echo "  (none defined for this role)"
fi
stop_if_layer_failed "Role-specific"

echo ""
echo "===== All layers passed: $PASS checks OK ====="
exit 0