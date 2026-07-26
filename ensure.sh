#!/usr/bin/env bash
# ensure.sh — the idempotent "make this machine ready" orchestrator.
# Safe to run any number of times. Fast when everything is already healthy.
#
# Usage:
#   ensure.sh              # repair only what is missing/broken
#   ensure.sh --force      # re-run every step regardless of health
#   ensure.sh --interactive # allow the one sudo prompt (creating /goinfre)
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

FORCE=0; INTERACTIVE=""
for a in "$@"; do
  case "$a" in
    --force)       FORCE=1 ;;
    --interactive) INTERACTIVE=--interactive ;;
  esac
done

# healthy : cheap check that nothing needs doing. Anything the store losing its
# contents would break is checked here, because that is what a machine switch does.
healthy() {
  local store droot mode
  store="$(cat "$VS_STORE_RECORD" 2>/dev/null)" || return 1
  [ -n "$store" ] && [ -d "$store" ] && [ -w "$store" ] || return 1

  [ -x "$VS_BIN_DIR/code" ] || return 1                      # the shim in your home
  vscode_installed || return 1                               # the app on the store

  # Extensions must be a live symlink onto the store — EXCEPT while the one-time
  # move is waiting for VSCode to close. That wait is by design, so treat it as
  # healthy; otherwise every terminal would re-provision for nothing.
  if [ -L "$HOME/.vscode/extensions" ]; then
    [ -d "$HOME/.vscode/extensions" ] || return 1            # store wiped under it
  elif [ -d "$HOME/.vscode/extensions" ]; then
    vscode_is_running || return 1                            # closed now -> go move it
  fi

  droot="$(cat "$VS_STATE_DIR/droot" 2>/dev/null)" || return 1
  [ -d "$droot" ] || return 1
  [ -S "$VS_SOCK_LINK" ] || return 1                         # stable docker socket

  mode="$(cat "$VS_STATE_DIR/docker-mode" 2>/dev/null)"
  [ "$VS_DOCKER_MODE" = system ] || [ "$mode" != system ] || return 1
  case "$mode" in
    rootless) rootless_running || return 1; _rootless_env ;;
    system)   docker_running   || return 1 ;;
    *)        return 1 ;;
  esac
  ! _under_home "$(docker_data_root)"
}

if [ "$FORCE" -eq 0 ] && healthy; then
  touch_marker last-ok
  exit 0
fi

info "provisioning this machine (login: $USER) ..."
store_dir $INTERACTIVE >/dev/null || { error "no usable store (goinfre/tmp)"; exit 1; }
info "store: $(store_dir)"
[ -n "$INTERACTIVE" ] && ensure_linger $INTERACTIVE >/dev/null 2>&1 || true

rc=0
ensure_vscode || rc=1
ensure_docker || rc=1

if [ "$rc" -eq 0 ]; then
  touch_marker last-ok
  ok "ready. In a project: 'devbox init angular|dotnet|cpp|base', then Reopen in Container."
else
  warn "finished with warnings — run 'setup-doctor' to see details ($(_vs_log_file))"
fi
exit "$rc"
