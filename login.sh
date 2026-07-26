# shellcheck shell=bash
# login.sh — sourced from ~/.bashrc AND ~/.zshrc on every shell. MUST be fast and
# MUST NOT break the shell (no `set -e`, no `exit`, guard everything). Its job:
#   1. export PATH + DOCKER_HOST so `code` / `devbox` / `docker` just work
#   2. if the machine looks unprovisioned or stale, run ensure.sh
#
# The heavy check runs at most once per $VS_HEALTH_TTL_MIN, so extra terminals
# opened during a session stay instant.

: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"
if [ -r "$VS_SETUP_HOME/config.sh" ]; then
  . "$VS_SETUP_HOME/config.sh"
  . "$VS_SETUP_HOME/lib/common.sh"

  # --- always: cheap PATH / env exports ---
  # $VS_BIN_DIR holds the `code` shim; $VS_SETUP_HOME/bin holds devbox + doctor.
  case ":$PATH:" in *":$VS_BIN_DIR:"*) ;; *) PATH="$VS_BIN_DIR:$PATH";; esac
  case ":$PATH:" in *":$VS_SETUP_HOME/bin:"*) ;; *) PATH="$VS_SETUP_HOME/bin:$PATH";; esac
  export PATH

  # Point the docker CLI at OUR daemon when that is how this machine is set up.
  if [ -r "$VS_STATE_DIR/docker-host" ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"
    export DOCKER_HOST
  fi
  # The stable socket path the dev-container templates mount.
  [ -S "$VS_SOCK_LINK" ] && export DEVBOX_DOCKER_SOCK="$VS_SOCK_LINK"

  # --- conditionally: provision this machine ---
  if ! fresh "$VS_STATE_DIR/last-ok" "${VS_HEALTH_TTL_MIN:-60}"; then
    if [ -t 1 ] && [ -z "${VS_SETUP_QUIET:-}" ]; then
      # Interactive first login on this machine: run in the foreground so docker
      # is ready before you need it (once per machine / TTL window).
      "$VS_SETUP_HOME/ensure.sh"
    else
      # Non-interactive shells: never block; provision detached.
      ( "$VS_SETUP_HOME/ensure.sh" >/dev/null 2>&1 & ) 2>/dev/null
    fi
    if [ -r "$VS_STATE_DIR/docker-host" ]; then
      DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"; export DOCKER_HOST
    fi
    [ -S "$VS_SOCK_LINK" ] && export DEVBOX_DOCKER_SOCK="$VS_SOCK_LINK"
  fi
fi
