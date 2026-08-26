#!/usr/bin/env bash
# sync-and-run.sh — push repo + run a command on target
set -euo pipefail
TARGET="$1"; shift
rsync -avz --delete ~/prod-ready-fleet/ "$TARGET":~/prod-ready-fleet/
ssh "$TARGET" "cd ~/prod-ready-fleet && sudo $*"