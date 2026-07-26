# shellcheck shell=bash
# lib/vscode.sh — VSCode lives on the store (goinfre/tmp), beside its extensions.
#
# What stays in your 5G home:  the downloaded tar.gz (~150M), your settings, and
#                              the list of extensions you use.
# What lives on the store:     the extracted app (~1.1G), the extensions (~1.5G),
#                              and VSCode's own caches.
#
# A machine switch wipes the store. Nothing is lost: the app is re-extracted from
# the tarball already in your home (no download), and your extensions are
# reinstalled from the saved list. The `code` command is a small shim in your
# home, so it never becomes "command not found" while that is happening.

vscode_dir()       { store_path vscode "${1:-}"; }
vscode_app_dir()   { echo "$(vscode_dir "${1:-}")/VSCode-linux-x64"; }
vscode_bin()       { echo "$(vscode_app_dir "${1:-}")/bin/code"; }
vscode_installed() { [ -x "$(vscode_bin)" ]; }
vscode_version()   { "$(vscode_bin)" --version 2>/dev/null | head -1; }

# _vs_tarball : where the download is kept. In your home by default (341M today)
# so landing on a fresh machine costs no download. Set VS_CACHE_TARBALL=0 to keep
# it on the store instead: your home stays smaller, and every machine switch pays
# one download.
_vs_tarball() {
  if [ "${VS_CACHE_TARBALL:-1}" = 1 ]; then echo "$VS_CACHE_DIR/vscode-stable.tar.gz"
  else echo "$(vscode_dir)/vscode-stable.tar.gz"; fi
}

# vscode_is_running : any VSCode of yours running right now? Moving the app or the
# extensions folder out from under a live editor is how you break the editor you
# are sitting in, so the one-time moves wait until it is closed.
vscode_is_running() {
  pgrep -u "$(id -u)" -f '/code(-insiders)?( |$)|VSCode-linux-x64/code|/usr/share/code/code' \
    >/dev/null 2>&1
}

# ensure_tarball [--refresh] : keep one VSCode download in the home cache.
ensure_tarball() {
  local tb; tb="$(_vs_tarball)"
  mkdir -p "$VS_CACHE_DIR"
  if [ -s "$tb" ] && [ "${1:-}" != "--refresh" ]; then return 0; fi
  info "downloading VSCode (kept in $VS_CACHE_DIR, reused on every machine) ..."
  if fetch "$VS_CODE_URL" "$tb.part"; then
    mv -f "$tb.part" "$tb"; return 0
  fi
  rm -f "$tb.part"
  [ -s "$tb" ] && { warn "download failed — keeping the copy already cached"; return 0; }
  error "could not download VSCode"; return 1
}

# migrate_legacy_vscode : the old layout kept the app in ~/vsCodeInstaller, which
# is exactly the 1.1G we are trying to get out of your home. Move it onto the
# store instead of downloading it again, then drop the old folder.
migrate_legacy_vscode() {
  local old="$VS_LEGACY_INSTALLER_DIR/VSCode-linux-x64" app
  [ -d "$old" ] || return 0
  if pgrep -u "$(id -u)" -f "$VS_LEGACY_INSTALLER_DIR" >/dev/null 2>&1; then
    warn "VSCode is running from $VS_LEGACY_INSTALLER_DIR — close it, then run 'setup-doctor fix'"
    return 0
  fi
  app="$(vscode_app_dir)" || return 0
  if [ ! -x "$app/bin/code" ]; then
    info "moving VSCode out of your home -> $app (this takes a moment, once) ..."
    mkdir -p "$(dirname "$app")"
    rmdir "$app" 2>/dev/null
    if mv "$old" "$app" 2>/dev/null; then ok "VSCode now lives on the store"
    else warn "could not move the old install; will extract a fresh copy instead"; return 0; fi
  fi
  rm -rf "$VS_LEGACY_INSTALLER_DIR"
  info "removed the old $VS_LEGACY_INSTALLER_DIR (freed ~1.1G of home)"
}

# install_vscode [--refresh] : put the app on the store, from the cached tarball.
install_vscode() {
  local dir tb
  dir="$(vscode_dir --interactive)" || { error "no store for VSCode"; return 1; }
  ensure_tarball "${1:-}" || return 1
  tb="$(_vs_tarball)"
  info "extracting VSCode into $dir ..."
  rm -rf "$dir/VSCode-linux-x64.old"
  [ -d "$dir/VSCode-linux-x64" ] && mv "$dir/VSCode-linux-x64" "$dir/VSCode-linux-x64.old"
  if tar -xzf "$tb" -C "$dir"; then
    rm -rf "$dir/VSCode-linux-x64.old"
  else
    error "failed to extract VSCode"
    [ -d "$dir/VSCode-linux-x64.old" ] && mv "$dir/VSCode-linux-x64.old" "$dir/VSCode-linux-x64"
    return 1
  fi
  ensure_code_shim
  _vs_set_keybinding
  vscode_installed && ok "VSCode installed: $(vscode_version)"
}

# ensure_code_shim : `code` (and `code-tunnel`) as tiny scripts in your home that
# find the real binary on the store, and rebuild it first if the store was wiped.
ensure_code_shim() {
  local b
  mkdir -p "$VS_BIN_DIR"
  for b in code code-tunnel; do
    cat > "$VS_BIN_DIR/$b" <<EOF
#!/usr/bin/env bash
# written by devbox — finds VSCode on goinfre/tmp, rebuilding it if that was wiped.
: "\${VS_SETUP_HOME:=\$HOME/.config/vscode-setup}"
. "\$VS_SETUP_HOME/config.sh"
. "\$VS_SETUP_HOME/lib/common.sh"
. "\$VS_SETUP_HOME/lib/vscode.sh"
real="\$(vscode_app_dir)/bin/$b"
if [ ! -x "\$real" ]; then
  "\$VS_SETUP_HOME/ensure.sh" || true
  real="\$(vscode_app_dir)/bin/$b"
fi
[ -x "\$real" ] || { echo "devbox: VSCode is not available (see: setup-doctor)" >&2; exit 1; }
exec "\$real" "\$@"
EOF
    chmod +x "$VS_BIN_DIR/$b"
  done
}

# _vs_set_keybinding : GNOME shortcut Ctrl+Alt+C -> code-tunnel (best-effort).
# Points at the shim in your home, which survives a wiped store.
_vs_set_keybinding() {
  have gsettings || return 0
  local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
  local kpath="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
  gsettings set "$schema:$kpath" name    "OpenVSCode2"            2>/dev/null || return 0
  gsettings set "$schema:$kpath" command "$VS_BIN_DIR/code-tunnel" 2>/dev/null
  gsettings set "$schema:$kpath" binding "<Control><Alt>c"        2>/dev/null
  local list
  list="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)"
  case "$list" in
    *"$kpath"*) : ;;
    "@as []"|"[]"|"") gsettings set org.gnome.settings-daemon.plugins.media-keys \
                        custom-keybindings "['$kpath']" 2>/dev/null ;;
    *) gsettings set org.gnome.settings-daemon.plugins.media-keys \
         custom-keybindings "${list%]}, '$kpath']" 2>/dev/null ;;
  esac
}

# ensure_extensions_store : ~/.vscode/extensions is a symlink onto the store.
# One-time move keeps whatever is already installed. Re-links itself after a
# machine switch wipes the store out from under it.
ensure_extensions_store() {
  local link="$HOME/.vscode/extensions" target
  target="$(store_path "$VS_EXT_DIR_NAME")" || { warn "no store for extensions"; return 1; }

  if [ -L "$link" ]; then
    [ "$(readlink -f "$link" 2>/dev/null)" = "$(readlink -f "$target")" ] && return 0
    ln -sfn "$target" "$link"
    info "extensions dir re-linked -> $target (the store had been wiped)"
    return 0
  fi

  if [ -d "$link" ]; then
    if vscode_is_running; then
      warn "~/.vscode/extensions is still in your home ($(du -sh "$link" 2>/dev/null | cut -f1))"
      warn "close VSCode and run 'make install' (or 'setup-doctor fix') to move it — not while it is open"
      return 0
    fi
    info "moving ~/.vscode/extensions -> $target (one-time, off \$HOME) ..."
    rmdir "$target" 2>/dev/null
    if ! mv "$link" "$target" 2>/dev/null; then
      cp -a "$link"/. "$target"/ 2>/dev/null; rm -rf "$link"
    fi
  fi

  mkdir -p "$(dirname "$link")"
  ln -sfn "$target" "$link"
  ok "extensions dir -> $target"
}

# ensure_code_cache_store : VSCode's caches grow forever and are pure rebuildable
# junk. Send them to the store too. Your settings, keybindings, snippets and
# extension logins stay in your home.
ensure_code_cache_store() {
  local base="$HOME/.config/Code" target d link name
  if vscode_is_running; then
    info "skipping the VSCode cache move while VSCode is open (run 'setup-doctor fix' after closing it)"
    return 0
  fi
  target="$(store_path "$VS_CODE_CACHE_NAME")" || return 1
  mkdir -p "$base/User"
  for d in CachedData CachedProfilesData CachedExtensionVSIXs Cache "Code Cache" \
           GPUCache logs "Service Worker" blob_storage User/workspaceStorage; do
    name="$(basename "$d")"
    link="$base/$d"
    mkdir -p "$target/$name"
    if [ ! -L "$link" ] && [ -e "$link" ]; then rm -rf "${link:?}"; fi   # pure cache
    mkdir -p "$(dirname "$link")"
    ln -sfn "$target/$name" "$link"
  done
}

# save_extension_manifest [--force] : remember what you have, so a wiped store
# can put it back. It never shrinks the list on its own: right after a machine
# switch the store is empty and the reinstall is still running, and overwriting
# then would lose the very list we need. Use --force after you really did remove
# extensions on purpose.
save_extension_manifest() {
  vscode_installed || return 0
  local tmp="$VS_EXT_MANIFEST.tmp.$$" n old=0
  mkdir -p "$(dirname "$VS_EXT_MANIFEST")"
  "$(vscode_bin)" --list-extensions 2>/dev/null | sed '/^$/d' | sort -u > "$tmp"
  n=$(wc -l < "$tmp" 2>/dev/null || echo 0)
  [ -s "$VS_EXT_MANIFEST" ] && old=$(wc -l < "$VS_EXT_MANIFEST")
  if [ "$n" -gt 0 ] && { [ "$n" -ge "$old" ] || [ "${1:-}" = "--force" ]; }; then
    mv -f "$tmp" "$VS_EXT_MANIFEST"
    info "extension list saved ($n entries)"
  else
    rm -f "$tmp"
  fi
}

# restore_extension_manifest : reinstall the saved list when the store came back
# empty. Runs in the background - it is a download, and you want the editor now.
restore_extension_manifest() {
  vscode_installed || return 0
  [ -s "$VS_EXT_MANIFEST" ] || return 0
  local have_n args=() e
  have_n=$("$(vscode_bin)" --list-extensions 2>/dev/null | sed '/^$/d' | wc -l)
  [ "$have_n" -gt 0 ] && return 0            # nothing was lost
  while read -r e; do [ -n "$e" ] && args+=(--install-extension "$e"); done < "$VS_EXT_MANIFEST"
  [ ${#args[@]} -gt 0 ] || return 0
  info "reinstalling your $(( ${#args[@]} / 2 )) extensions in the background (from the saved list) ..."
  ( "$(vscode_bin)" "${args[@]}" --force >>"$VS_STATE_DIR/extensions-restore.log" 2>&1 & ) 2>/dev/null
}

# ensure_host_extension : the one extension that must be there for containers.
ensure_host_extension() {
  vscode_installed || return 0
  local ext
  for ext in ${VS_HOST_EXTENSIONS}; do
    "$(vscode_bin)" --install-extension "$ext" --force >/dev/null 2>&1 \
      && info "host extension present: $ext" \
      || warn "could not install host extension: $ext"
  done
}

# ensure_extra_extensions [--force] : the editor you want (icons, theme, the
# drawing/image editors, Claude Code), from $VS_EXTRA_EXTENSIONS.
#
# Installed once and then left alone: a marker in your home says "done", so this
# never re-installs something you deliberately removed, and never costs a
# marketplace round-trip on a login where there is nothing to do. After a machine
# switch they come back from the saved list like every other extension - the
# marker is in your home, so this step stays quiet.
#
# --force ignores the marker and installs whatever is missing from the list
# (what `devbox ext extras` runs after you edit the list in config.sh).
ensure_extra_extensions() {
  vscode_installed || return 0
  local force=0
  case "${1:-}" in --force) force=1;; esac
  [ -n "${VS_EXTRA_EXTENSIONS:-}" ] || return 0
  [ "$force" -eq 1 ] || ! [ -f "$VS_STATE_DIR/extras-installed" ] || return 0

  local have args=() e
  have="$("$(vscode_bin)" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')" || have=""
  for e in $VS_EXTRA_EXTENSIONS; do
    printf '%s\n' "$have" | grep -Fxq "$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')" \
      || args+=(--install-extension "$e")
  done
  [ ${#args[@]} -gt 0 ] || { touch_marker extras-installed; return 0; }

  info "installing $(( ${#args[@]} / 2 )) extra extensions in the background (see 'devbox ext extras')"
  (
    if "$(vscode_bin)" "${args[@]}" --force >>"$VS_STATE_DIR/extensions-extras.log" 2>&1; then
      touch_marker extras-installed
      save_extension_manifest        # so a wiped store puts them back too
    fi
  ) >/dev/null 2>&1 &
}

# ensure_vscode : the orchestrated entry point.
ensure_vscode() {
  ensure_code_shim
  migrate_legacy_vscode
  if ! vscode_installed; then
    install_vscode || { warn "VSCode install failed (will retry next login)"; return 1; }
  elif ! fresh "$VS_STATE_DIR/vscode-checked" $((VS_UPDATE_INTERVAL_HRS * 60)); then
    info "checking for a newer VSCode in the background ..."
    ( install_vscode --refresh >/dev/null 2>&1 && touch_marker vscode-checked ) &
  fi
  touch_marker vscode-checked
  ensure_extensions_store
  ensure_code_cache_store
  ensure_host_extension
  restore_extension_manifest
  ensure_extra_extensions
  save_extension_manifest
}
