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
  gnome_keybinding 0 "OpenVSCode2" "$VS_BIN_DIR/code-tunnel" "<Control><Alt>c"
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

# _vs_code_dirs_home : VSCode's own folders belong in your home. All of them.
#
# devbox used to symlink ten of them onto the store. Two reasons that was wrong,
# and neither is about size:
#   * some of them are not caches at all. workspaceStorage records what you were
#     working on, and the logs record what your extensions printed - putting that
#     on a shared machine's local disk, where it outlives your logout, is a
#     privacy bug, not an optimisation.
#   * the rest are 56M, of which 43M is CachedData that VSCode rebuilds on its
#     next start. That is 1% of a 5G home. It never justified a symlink dance
#     with a migration, a re-link path and a "did you close VSCode" guard.
#
# So: one function, run once, that puts everything back and deletes the copy on
# the store. What stays on the store is what is actually big and actually
# rebuildable - VSCode itself, the extensions, and docker.
#
# The test below is "is it a directory", not "is it a symlink". That distinction
# is the whole bug: a symlink pointing at a wiped store is not a directory and
# not a valid target either, and VSCode reports it as "already exists but is not
# a directory" and fails EVERY extension install, because each one stages its
# .vsix through CachedExtensionVSIXs. Checking -L alone also walked past a plain
# leftover file, which breaks the same way. Anything that is not a directory
# gets replaced by one.
_vs_code_dirs_home() {
  local base="$HOME/.config/Code" d link tgt moved=0
  for d in logs "Service Worker" blob_storage User/workspaceStorage \
           CachedData CachedProfilesData CachedExtensionVSIXs Cache "Code Cache" GPUCache; do
    link="$base/$d"
    [ -e "$link" ] || [ -L "$link" ] || continue     # absent: VSCode makes it
    [ -d "$link" ] && [ ! -L "$link" ] && continue   # already a real folder: fine
    tgt="$(readlink -f "$link" 2>/dev/null)"
    rm -rf "$link"
    mkdir -p "$link"
    if [ -n "$tgt" ] && [ -d "$tgt" ] && [ "$tgt" != "$link" ]; then
      cp -a "$tgt"/. "$link"/ 2>/dev/null
      rm -rf "$tgt"
    fi
    moved=1
  done
  [ "$moved" = 1 ] && ok "VSCode's own folders are real directories in your home again (extension installs need that)"

  # The now-empty shell of the old layout.
  local old; old="${VS_STORE:-}"
  [ -n "$old" ] && rmdir "$old/$VS_CODE_CACHE_NAME" 2>/dev/null
  return 0
}

# --- installing extensions ----------------------------------------------------
#
# Every extension install in here goes through _vs_install_batch, for one reason:
# an install that fails must leave a trace that the NEXT login can act on.
#
# The bug this exists to prevent really happened. ~/.config/Code/CachedExtensionVSIXs
# was a dangling symlink onto a wiped store; every install stages its .vsix through
# that folder, so nine extensions failed in one batch. The output went to a log
# nobody reads, ensure_vscode returned success, and the six that were lost never
# came back - because every recovery path read "some extensions are present" as
# "nothing is wrong". Recording the failures is what turns that into a retry.

# _vs_pending : ids whose last install attempt failed. The retry list.
_vs_pending() { echo "$VS_STATE_DIR/extensions-pending"; }

# _vs_note_wipe_state : did this machine come up with an empty extensions folder?
#
# Must be called BEFORE anything installs, and that is the whole point of it
# being separate. The obvious version - have restore_extension_manifest count
# what is installed and call zero "wiped" - is correct only if nothing installed
# anything first. ensure_host_extension does exactly that, so by the time the
# restore looked, one extension existed and a wiped store read as a healthy one:
# eight extensions went missing and seven of them stayed missing.
#
# Reading the folder rather than asking VSCode also makes this cheap enough to
# do unconditionally, and independent of whatever order the callers run in.
_vs_note_wipe_state() {
  local dir n
  dir="$(readlink -f "$HOME/.vscode/extensions" 2>/dev/null)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then _VS_STORE_WAS_WIPED=1; return 0; fi
  # extensions.json is VSCode's own index, not an extension.
  n=$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
  [ "$n" -eq 0 ] && _VS_STORE_WAS_WIPED=1 || _VS_STORE_WAS_WIPED=0
  return 0
}

# _vs_norm_ids <file> : de-duplicate a list of extension ids, in place.
#
# Extension ids are case-insensitive, and the two places we get them from
# disagree on case: config.sh is written the way the marketplace displays them
# (PKief.material-icon-theme) and `code --list-extensions` answers in lower case
# (pkief.material-icon-theme). A plain `sort -u` keeps both, and then the saved
# list claims ten extensions for eight, and every comparison against it reports
# phantom missing ones. Lower case is the canonical form: it is what VSCode
# reports, and what it accepts on install.
_vs_norm_ids() {
  tr '[:upper:]' '[:lower:]' < "$1" | sed '/^$/d' | sort -u > "$1.norm.$$" \
    && mv -f "$1.norm.$$" "$1"
}

# _vs_have_ext : is <id> installed right now? (ids are case-insensitive)
_vs_have_ext() {
  local want; want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "${_VS_HAVE_CACHE-}" | grep -Fxq "$want"
}

# _vs_refresh_have : fill the cache the two callers above share, once per run.
_vs_refresh_have() {
  _VS_HAVE_CACHE="$("$(vscode_bin)" --list-extensions 2>/dev/null \
    | sed '/^$/d' | tr '[:upper:]' '[:lower:]' | sort -u)"
}

# _vs_install_batch <logname> <id>... : install them, then check what really
# landed rather than trusting the exit code.
#
# `code --install-extension` exits non-zero on failure, but it fails PER
# EXTENSION and keeps going, so the exit code cannot tell you WHICH ones. The
# only trustworthy answer is to re-list afterwards and compare. Whatever is
# still missing goes on the pending list, and the user is told - once, with the
# reason, not buried in a log.
#
# Returns 0 only when every id asked for is present afterwards.
_vs_install_batch() {
  local logname="$1"; shift
  [ $# -gt 0 ] || return 0
  local log="$VS_STATE_DIR/$logname" args=() e failed=() gb

  # Disk is the other way these fail. A marketplace .vsix is unpacked into the
  # store, so a store with no room fails every install with an I/O error that
  # says nothing about disk. Say it here instead of letting them guess.
  gb=$(avail_gb "$(store_dir)")
  if [ "$gb" -lt 1 ]; then
    warn "the store has ${gb}G free — extension installs will fail. Run 'devbox gc', then 'devbox ext retry'"
    printf '%s\n' "$@" >> "$(_vs_pending)"
    sort -u -o "$(_vs_pending)" "$(_vs_pending)" 2>/dev/null
    return 1
  fi

  mkdir -p "$VS_STATE_DIR"
  for e in "$@"; do args+=(--install-extension "$e"); done
  "$(vscode_bin)" "${args[@]}" --force >>"$log" 2>&1

  _vs_refresh_have
  for e in "$@"; do _vs_have_ext "$e" || failed+=("$e"); done

  if [ ${#failed[@]} -eq 0 ]; then
    # Anything we just installed is no longer pending.
    if [ -s "$(_vs_pending)" ]; then
      local keep; keep="$(grep -Fvx -f <(printf '%s\n' "$@") "$(_vs_pending)" 2>/dev/null)"
      printf '%s' "${keep:+$keep$'\n'}" > "$(_vs_pending)"
      [ -s "$(_vs_pending)" ] || rm -f "$(_vs_pending)"
    fi
    return 0
  fi

  printf '%s\n' "${failed[@]}" >> "$(_vs_pending)"
  sort -u -o "$(_vs_pending)" "$(_vs_pending)" 2>/dev/null
  warn "${#failed[@]} extension(s) did not install: ${failed[*]}"

  # The reason, from the log, in the user's words rather than a stack trace.
  # Take the last run's errors only - the log is appended to across logins, and
  # quoting a failure from three days ago is worse than quoting nothing.
  local why
  why="$(sed -n '/^Installing extensions\.\.\./,$p' "$log" 2>/dev/null \
         | grep -m1 -E 'Error while installing|Failed Installing|EACCES|ENOSPC|ENOENT')"
  if [ -n "$why" ]; then
    warn "reason: $(printf '%s' "$why" | sed 's/.*(Error: //; s/)$//')"
  else
    warn "reason: nothing conclusive in $log (the id may not exist in the marketplace)"
  fi
  warn "they will be retried at next login, or now with: devbox ext retry"
  return 1
}

# save_extension_manifest [--force] : remember what you have, so a wiped store
# can put it back.
#
# It never shrinks on its own, and the way it does that matters. Comparing counts
# ("only write if the new list is at least as long") looked equivalent and was
# not: a run that listed one extension while the rest were mid-reinstall still
# had n >= old whenever the file was empty or a stub, and the saved list was
# overwritten down to a single entry - destroying the record of the seven
# extensions the restore was supposed to bring back.
#
# So: union. The manifest only ever gains ids. --force replaces it outright,
# which is how you drop something you removed on purpose.
save_extension_manifest() {
  vscode_installed || return 0
  local tmp="$VS_EXT_MANIFEST.tmp.$$" n
  mkdir -p "$(dirname "$VS_EXT_MANIFEST")"
  "$(vscode_bin)" --list-extensions 2>/dev/null | sed '/^$/d' > "$tmp"

  if [ ! -s "$tmp" ] && [ "${1:-}" != "--force" ]; then
    rm -f "$tmp"; return 0                    # listed nothing: never trust that
  fi
  if [ "${1:-}" != "--force" ] && [ -s "$VS_EXT_MANIFEST" ]; then
    cat "$VS_EXT_MANIFEST" >> "$tmp"
  fi
  _vs_norm_ids "$tmp"
  n=$(wc -l < "$tmp" 2>/dev/null || echo 0)
  mv -f "$tmp" "$VS_EXT_MANIFEST"
  info "extension list saved ($n entries)"
}

# restore_extension_manifest : put back what the saved list says you should have.
#
# The old test was "any extension present -> nothing was lost", which is only
# right when a store is wiped all-or-nothing. A batch that fails halfway leaves
# some installed, and that test then reads the wreckage as health. Compare
# against the list instead: install exactly what is missing.
#
# An extension you uninstalled on purpose is missing too, and we must not fight
# you over it. That is what the pending list is for - it holds only ids whose
# install ERRORED, so a deliberate removal is never in it. Missing-and-not-pending
# is left alone unless the store came back completely empty.
restore_extension_manifest() {
  vscode_installed || return 0
  local want=() e wiped

  # Recorded before anything installed - see _vs_note_wipe_state. Falling back to
  # a live count here would reintroduce the ordering bug it exists to prevent, so
  # when no one recorded it, take the reading now and accept it may be late.
  if [ -z "${_VS_STORE_WAS_WIPED:-}" ]; then _vs_note_wipe_state; fi
  wiped="${_VS_STORE_WAS_WIPED:-0}"
  _vs_refresh_have

  # 1. anything whose install errored last time, always.
  if [ -s "$(_vs_pending)" ]; then
    while read -r e; do
      [ -n "$e" ] && ! _vs_have_ext "$e" && want+=("$e")
    done < "$(_vs_pending)"
  fi
  # 2. after a full wipe, the whole saved list too.
  if [ "$wiped" = 1 ] && [ -s "$VS_EXT_MANIFEST" ]; then
    while read -r e; do
      [ -n "$e" ] && want+=("$e")
    done < "$VS_EXT_MANIFEST"
  fi
  [ ${#want[@]} -gt 0 ] || return 0

  # de-duplicate
  local uniq=(); while read -r e; do [ -n "$e" ] && uniq+=("$e"); done \
    < <(printf '%s\n' "${want[@]}" | sort -u)

  info "reinstalling ${#uniq[@]} extension(s) in the background ($([ "$wiped" = 1 ] && echo 'the store had been wiped' || echo 'they failed last time')) ..."
  # Tells the two steps that run after this one to stand down. They install from
  # subsets of the same list, and `code --install-extension` is not safe to run
  # twice at once against one extensions folder - the second process can see a
  # half-unpacked directory from the first and either clobber it or call it
  # installed. One installer at a time; the others get their turn next login,
  # by which point there is nothing left for them to do.
  _VS_RESTORE_IN_FLIGHT=1
  ( _vs_install_batch extensions-restore.log "${uniq[@]}" >/dev/null 2>&1 & ) 2>/dev/null
}

# ensure_host_extension : the one extension that must be there for containers.
# Only installs what is actually missing - the old version re-forced it on every
# single login, which is a marketplace round-trip to be told nothing changed.
ensure_host_extension() {
  vscode_installed || return 0
  [ "${_VS_RESTORE_IN_FLIGHT:-0}" = 1 ] && return 0   # the restore covers it
  local ext missing=()
  _vs_refresh_have
  for ext in ${VS_HOST_EXTENSIONS}; do
    _vs_have_ext "$ext" || missing+=("$ext")
  done
  [ ${#missing[@]} -gt 0 ] || return 0
  _vs_install_batch extensions-host.log "${missing[@]}"
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
#
# The marker is only written when every extra really did land. It used to be
# written whenever the install command exited 0, and that command exits 0 in
# cases where individual extensions failed - so one bad batch could mark the
# whole step "done" forever with half the list missing.
ensure_extra_extensions() {
  vscode_installed || return 0
  local force=0
  case "${1:-}" in --force) force=1;; esac
  [ -n "${VS_EXTRA_EXTENSIONS:-}" ] || return 0
  [ "$force" -eq 1 ] || ! [ -f "$VS_STATE_DIR/extras-installed" ] || return 0
  # A restore is already installing from a list that contains these.
  [ "${_VS_RESTORE_IN_FLIGHT:-0}" = 1 ] && [ "$force" -eq 0 ] && return 0

  local missing=() e
  _vs_refresh_have
  for e in $VS_EXTRA_EXTENSIONS; do
    _vs_have_ext "$e" || missing+=("$e")
  done
  [ ${#missing[@]} -gt 0 ] || { touch_marker extras-installed; return 0; }

  info "installing ${#missing[@]} extra extensions in the background (see 'devbox ext extras')"
  (
    if _vs_install_batch extensions-extras.log "${missing[@]}"; then
      touch_marker extras-installed
      save_extension_manifest        # so a wiped store puts them back too
    fi
  ) >/dev/null 2>&1 &
}

# repair_extensions : the "it is missing things and I do not care why" button.
#
# Rebuilds the saved list from the three sources that define what you should
# have - what is installed, the host extension, and your extras - then installs
# everything on it that is not there. This is the recovery path for a machine
# whose manifest was already damaged before the fixes above existed.
repair_extensions() {
  vscode_installed || { error "VSCode is not installed"; return 1; }
  local want=() e missing=()

  _vs_refresh_have
  mkdir -p "$(dirname "$VS_EXT_MANIFEST")"
  { printf '%s\n' "${_VS_HAVE_CACHE-}"
    [ -s "$VS_EXT_MANIFEST" ] && cat "$VS_EXT_MANIFEST"
    printf '%s\n' $VS_HOST_EXTENSIONS
    printf '%s\n' ${VS_EXTRA_EXTENSIONS:-}
  } > "$VS_EXT_MANIFEST.tmp.$$"
  _vs_norm_ids "$VS_EXT_MANIFEST.tmp.$$"
  mv -f "$VS_EXT_MANIFEST.tmp.$$" "$VS_EXT_MANIFEST"
  info "saved list rebuilt: $(wc -l < "$VS_EXT_MANIFEST") entries"

  while read -r e; do
    [ -n "$e" ] && ! _vs_have_ext "$e" && missing+=("$e")
  done < "$VS_EXT_MANIFEST"

  if [ ${#missing[@]} -eq 0 ]; then
    ok "every extension on your list is installed"
    rm -f "$(_vs_pending)"
    return 0
  fi
  info "installing ${#missing[@]} missing extension(s): ${missing[*]}"
  if _vs_install_batch extensions-repair.log "${missing[@]}"; then
    ok "all ${#missing[@]} installed"
    touch_marker extras-installed
    return 0
  fi
  return 1
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

  # Order matters, and each step below depends on the one above it:
  #   the extensions folder must point at this machine's store before we can ask
  #   what is in it; what is in it must be read before anything installs, or a
  #   wiped store looks healthy; VSCode's own folders must be real directories
  #   before any install, or every one of them fails; and only then is it worth
  #   installing anything.
  ensure_extensions_store
  _vs_note_wipe_state
  _vs_code_dirs_home
  restore_extension_manifest      # sets _VS_RESTORE_IN_FLIGHT when it starts
  ensure_host_extension           # both of these stand down if it did
  ensure_extra_extensions
  save_extension_manifest
}
