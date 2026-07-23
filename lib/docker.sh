# shellcheck shell=bash
# lib/docker.sh — keep docker's heavy data OFF your 5G home.
#
# The invariant we enforce: docker's data-root must live on goinfre/tmp (or at
# least on local disk), never under $HOME. How we achieve it depends on how
# docker is provided on the machine:
#   * rootless docker  -> we own the daemon: set data-root and restart it.
#   * system docker     -> if its data-root is already off $HOME, we leave it;
#                          if it is under $HOME, we try to switch you to rootless.
#   * nothing running   -> bootstrap rootless docker into goinfre/tmp.

docker_running()    { docker info >/dev/null 2>&1; }
docker_is_rootless(){ docker info 2>/dev/null | grep -qi 'rootless'; }
docker_data_root()  { docker info -f '{{.DockerRootDir}}' 2>/dev/null; }

_under_home() { case "$1" in "$HOME"/*|"$HOME") return 0;; *) return 1;; esac; }

_rootless_env() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
}

# _write_daemon_json <data-root> : point rootless dockerd at <data-root>.
_write_daemon_json() {
  local droot="$1" cfg="$HOME/.config/docker/daemon.json"
  mkdir -p "$(dirname "$cfg")"
  cat > "$cfg" <<EOF
{
  "data-root": "$droot"
}
EOF
}

# _restart_rootless : restart the rootless daemon so daemon.json takes effect.
_restart_rootless() {
  _rootless_env
  if systemctl --user cat docker >/dev/null 2>&1; then
    systemctl --user restart docker >/dev/null 2>&1
  else
    pkill -f dockerd-rootless.sh >/dev/null 2>&1
    if have dockerd-rootless.sh; then
      nohup dockerd-rootless.sh >"$VS_STATE_DIR/dockerd.log" 2>&1 &
    fi
  fi
  local i
  for i in $(seq 1 30); do docker_running && return 0; sleep 0.5; done
  return 1
}

# _bootstrap_rootless <data-root> : set up rootless docker from scratch.
_bootstrap_rootless() {
  local droot="$1"
  _rootless_env
  if have dockerd-rootless-setuptool.sh; then
    info "setting up rootless docker (no root needed) ..."
    dockerd-rootless-setuptool.sh install >>"$VS_STATE_DIR/rootless-setup.log" 2>&1 || \
      warn "rootless setuptool reported issues (see rootless-setup.log)"
  else
    warn "dockerd-rootless-setuptool.sh not found; cannot bootstrap rootless docker"
    return 1
  fi
  _write_daemon_json "$droot"
  _restart_rootless
}

# _record_mode <mode> [docker-host] : persist how docker is reached so login.sh
# can export DOCKER_HOST only when we actually run rootless.
_record_mode() {
  mkdir -p "$VS_STATE_DIR"
  printf '%s\n' "$1" > "$VS_STATE_DIR/docker-mode"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$VS_STATE_DIR/docker-host"
  else rm -f "$VS_STATE_DIR/docker-host"; fi
}

# ensure_docker : the orchestrated entry point. Returns 0 if docker is usable.
ensure_docker() {
  have docker || { warn "docker command not found"; return 1; }

  local store droot
  store="$(pick_store)" || { error "no usable storage (goinfre/tmp)"; return 1; }
  droot="$store/docker/data"
  mkdir -p "$droot"
  printf '%s\n' "$droot" > "$VS_STATE_DIR/droot"

  if docker_running; then
    local cur; cur="$(docker_data_root)"
    if docker_is_rootless; then
      if [ "$cur" != "$droot" ]; then
        info "relocating rootless docker data -> $droot"
        _write_daemon_json "$droot"
        _restart_rootless || warn "restart after relocation failed"
      fi
      _rootless_env
      _record_mode rootless "$DOCKER_HOST"
    else
      # System docker (docker group). We cannot move its data-root without root.
      if _under_home "$cur"; then
        warn "system docker stores data under \$HOME ($cur) — switching to rootless"
        if _bootstrap_rootless "$droot"; then
          _rootless_env; _record_mode rootless "$DOCKER_HOST"
        else
          warn "staying on system docker; watch your home quota"
          _record_mode system
        fi
      else
        info "system docker data-root at $cur (off \$HOME) — leaving as-is"
        _record_mode system
      fi
    fi
  else
    _bootstrap_rootless "$droot" && { _rootless_env; _record_mode rootless "$DOCKER_HOST"; } \
      || { warn "could not start docker"; return 1; }
  fi

  if docker_running; then
    ok "docker ready — data-root: $(docker_data_root)"
    return 0
  fi
  error "docker is not responding"
  return 1
}
