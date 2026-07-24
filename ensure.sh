#!/usr/bin/env bash
# ensure.sh — the idempotent "make this machine ready" orchestrator.
# Safe to run any number of times. Fast when everything is already healthy.
#
# Usage:
#   ensure.sh            # repair only what is missing/broken
#   ensure.sh --force    # re-run every step regardless of health
set -uo pipefail

VS_SETUP_HOME="${VS_SETUP_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
. "$VS_SETUP_HOME/config.sh"
# shellcheck source=/dev/null
. "$VS_SETUP_HOME/lib/common.sh"
# shellcheck source=/dev/null
. "$VS_SETUP_HOME/lib/vscode.sh"
# shellcheck source=/dev/null
. "$VS_SETUP_HOME/lib/docker.sh"

mkdir -p "$VS_STATE_DIR"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# healthy : cheap-ish check that nothing needs doing.
healthy() {
  vscode_installed || return 1
  local droot; droot="$(cat "$VS_STATE_DIR/droot" 2>/dev/null)" || return 1
  [ -d "$droot" ] || return 1          # goinfre/tmp wiped on machine switch -> unhealthy
  docker_running || return 1
  [ -L "$HOME/.vscode/extensions" ] || return 1
  [ -d "$HOME/.vscode/extensions" ] || return 1  # symlink target gone (goinfre/tmp wiped)
  ! _under_home "$(docker_data_root)"  # data must not be back under HOME
}

if [ "$FORCE" -eq 0 ] && healthy; then
  touch_marker last-ok
  exit 0
fi

info "provisioning this machine (login: $USER) ..."

rc=0
ensure_vscode || rc=1
ensure_docker  || rc=1

# Make the dev-container helper + templates reachable and scaffold nothing else.
if [ "$rc" -eq 0 ]; then
  touch_marker last-ok
  ok "ready. Open a project and run 'devbox init dotnet|angular|cpp|base' then reopen in container."
else
  warn "finished with warnings — run 'setup-doctor' to see details ($(_vs_log_file))"
fi
exit "$rc"
