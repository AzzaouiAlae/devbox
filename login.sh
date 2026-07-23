# shellcheck shell=bash
# login.sh — sourced from ~/.zshrc on every shell. MUST be fast and MUST NOT
# break the shell (no `set -e`, no `exit`, guard everything). Its job:
#   1. export PATH + DOCKER_HOST so `code`/`devbox`/`docker` just work
#   2. if the machine looks unprovisioned or stale, run ensure.sh
#
# The heavy check runs at most once per $VS_HEALTH_TTL_MIN, so extra terminals
# opened during a session stay instant.

# Resolve setup home without assuming CWD.
: "${VS_SETUP_HOME:=$HOME/.config/vscode-setup}"
if [ -r "$VS_SETUP_HOME/config.sh" ]; then
  . "$VS_SETUP_HOME/config.sh"
  . "$VS_SETUP_HOME/lib/common.sh"

  # --- always: cheap PATH / env exports ---
  case ":$PATH:" in *":$VS_HOME/bin:"*) ;; *) PATH="$VS_HOME/bin:$PATH";; esac
  case ":$PATH:" in *":$VS_SETUP_HOME/bin:"*) ;; *) PATH="$VS_SETUP_HOME/bin:$PATH";; esac
  export PATH

  # Point the docker CLI at our rootless socket only if that is how we set it up.
  if [ -r "$VS_STATE_DIR/docker-host" ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"
  fi

  # --- conditionally: provision this machine ---
  if ! fresh "$VS_STATE_DIR/last-ok" "${VS_HEALTH_TTL_MIN:-60}"; then
    if [ -t 1 ] && [ -z "${VS_SETUP_QUIET:-}" ]; then
      # Interactive first login on this machine: run in foreground so docker is
      # ready before you need it (only happens once per machine / TTL window).
      "$VS_SETUP_HOME/ensure.sh"
    else
      # Non-interactive shells: never block; provision detached.
      ( "$VS_SETUP_HOME/ensure.sh" >/dev/null 2>&1 & ) 2>/dev/null
    fi
    # Re-export DOCKER_HOST in case ensure.sh just created the rootless socket.
    if [ -r "$VS_STATE_DIR/docker-host" ]; then
      export DOCKER_HOST="$(cat "$VS_STATE_DIR/docker-host" 2>/dev/null)"
    fi
  fi
fi
