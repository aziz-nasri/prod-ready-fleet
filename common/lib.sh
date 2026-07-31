#!/usr/bin/env bash

# the logging functions
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "${LOG_FILE:-/var/log/lab-bootstrap.log}"; }
log_warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" | tee -a "${LOG_FILE:-/var/log/lab-bootstrap.log}" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE:-/var/log/lab-bootstrap.log}" >&2; }

# die function (error handling)
die() { log_error "$*"; exit 1; }

# trap clean_up function
trap_cleanup() {
  local exit_code=$?
  [[ $exit_code -ne 0 ]] && log_error "Script failed with exit code $exit_code"
  # any cleanup
}

# check privilege finction
require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root"
}

# Idempotency halpers
is_installed()      { dpkg -l "$1" &>/dev/null; }  
is_service_active() { systemctl is-active --quiet "$1"; }
is_service_enabled() { systemctl is-enabled --quiet "$1"; }
file_contains()      { grep -qF "$2" "$1" 2>/dev/null; }
