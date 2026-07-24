# shellcheck shell=bash
# lib/vscode.sh — install / update the latest VSCode into $VS_HOME and make
# sure the Dev Containers extension is present on the host.

# vscode_installed : true if the code binary exists and runs.
vscode_installed() { [ -x "$VS_HOME/bin/code" ]; }

# vscode_version : print installed version, or nothing.
vscode_version() { "$VS_HOME/bin/code" --version 2>/dev/null | head -1; }

# _vs_download_tarball <dest> : fetch latest stable linux-x64 vscode tarball.
_vs_download_tarball() {
  local dest="$1"
  if have curl; then
    curl -fL --retry 3 -o "$dest" "$VS_CODE_URL"
  elif have wget; then
    wget -q -O "$dest" "$VS_CODE_URL"
  else
    error "neither curl nor wget available to download VSCode"; return 1
  fi
}

# install_vscode : (re)install VSCode into $VS_INSTALLER_DIR from the latest
# tarball, matching the manual layout (~/vsCodeInstaller/VSCode-linux-x64), then
# delete the downloaded tarball.
install_vscode() {
  local tarball="$VS_INSTALLER_DIR/vsCode.tar.gz"
  mkdir -p "$VS_INSTALLER_DIR"
  info "downloading latest VSCode ..."
  if ! _vs_download_tarball "$tarball"; then rm -f "$tarball"; return 1; fi
  info "extracting VSCode into $VS_INSTALLER_DIR ..."
  # Tarball has a top-level VSCode-linux-x64/ dir; keep it (no --strip-components).
  if ! tar -xzf "$tarball" -C "$VS_INSTALLER_DIR"; then
    error "failed to extract VSCode tarball"; rm -f "$tarball"; return 1
  fi
  rm -f "$tarball"   # clean up the download once installed
  _vs_set_keybinding
  vscode_installed && ok "VSCode installed: $(vscode_version)"
}

# _vs_set_keybinding : GNOME shortcut Ctrl+Alt+C -> code-tunnel (best-effort).
# No-op off GNOME or when gsettings is unavailable. Also registers the custom
# binding in the keybindings list so it actually takes effect.
_vs_set_keybinding() {
  have gsettings || return 0
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
  local kpath="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
  gsettings set "$schema:$kpath" name    "OpenVSCode2"           2>/dev/null || return 0
  gsettings set "$schema:$kpath" command "$VS_HOME/bin/code-tunnel" 2>/dev/null
  gsettings set "$schema:$kpath" binding "<Control><Alt>c"       2>/dev/null
  local list
  list="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)"
  case "$list" in
    *"$kpath"*) : ;;                                   # already registered
    "@as []"|"[]"|"") gsettings set org.gnome.settings-daemon.plugins.media-keys \
                        custom-keybindings "['$kpath']" 2>/dev/null ;;
    *) gsettings set org.gnome.settings-daemon.plugins.media-keys \
         custom-keybindings "${list%]}, '$kpath']" 2>/dev/null ;;
  esac
  info "GNOME shortcut set: Ctrl+Alt+C -> code-tunnel"
}

# ensure_vscode : install if missing; otherwise refresh at most once/day.
ensure_vscode() {
  if ! vscode_installed; then
    install_vscode || { warn "VSCode install failed (will retry next login)"; return 1; }
  elif ! fresh "$VS_STATE_DIR/vscode-checked" $((VS_UPDATE_INTERVAL_HRS * 60)); then
    # Light-touch update: reinstall latest in the background so login stays fast.
    info "checking for VSCode updates in background ..."
    ( install_vscode >/dev/null 2>&1 && touch_marker vscode-checked ) &
  fi
  touch_marker vscode-checked
  ensure_extensions_store
  clean_extension_vsix_cache
  ensure_host_extension
}

# ensure_extensions_store : keep ~/.vscode/extensions on goinfre/tmp instead of
# $HOME — same ephemeral tier as docker data, since installed extensions (AI
# assistants, language packs, ...) can run into the hundreds of MB and are
# freely re-downloadable. ~/.vscode/extensions becomes a symlink onto the
# chosen store; a one-time move preserves whatever is already installed.
# Idempotent, and re-links (then reinstalls the host extension) after a
# machine switch wipes goinfre/tmp out from under the symlink.
ensure_extensions_store() {
  local link="$HOME/.vscode/extensions" store target
  store="$(pick_store)" || { warn "no usable storage for extensions dir (goinfre/tmp)"; return 1; }
  target="$store/vscode-extensions"
  mkdir -p "$target"

  if [ -L "$link" ]; then
    [ "$(cd "$target" && pwd)" = "$(readlink -f "$link" 2>/dev/null)" ] && return 0
    ln -sfn "$target" "$link"
    info "extensions dir re-linked -> $target (goinfre/tmp was wiped)"
    return 0
  fi

  if [ -d "$link" ]; then
    info "moving ~/.vscode/extensions -> $target (one-time, off \$HOME) ..."
    cp -a "$link"/. "$target"/ 2>/dev/null
    rm -rf "$link"
  fi

  mkdir -p "$(dirname "$link")"
  ln -sfn "$target" "$link"
  ok "extensions dir -> $target"
}

# clean_extension_vsix_cache : VS Code keeps every downloaded .vsix under this
# dir after installing it — pure cache, never cleaned on its own, and it just
# grows with every install/update. Safe to wipe; re-populated as needed.
clean_extension_vsix_cache() {
  local dir="$HOME/.config/Code/CachedExtensionVSIXs"
  [ -d "$dir" ] || return 0
  rm -rf "${dir:?}"/* 2>/dev/null
}

# ensure_host_extension : install the Dev Containers extension on the host once.
# This is the ONLY extension that lives in home; project extensions live in the
# container (on goinfre/tmp). Idempotent — --install-extension is a no-op if set.
ensure_host_extension() {
  vscode_installed || return 0
  local ext
  for ext in ${VS_HOST_EXTENSIONS}; do
    "$VS_HOME/bin/code" --install-extension "$ext" --force >/dev/null 2>&1 \
      && info "host extension present: $ext" \
      || warn "could not install host extension: $ext"
  done
}
