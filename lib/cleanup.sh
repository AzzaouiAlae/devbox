# shellcheck shell=bash
# lib/cleanup.sh — keep the 5G home from filling up with caches.
#
# Two things fill it without anyone asking: VSCode (see clean_vscode_caches in
# lib/vscode.sh) and your web browser. This file holds the browser half and the
# login hook that runs both.
#
# The rule for both is the same: delete only what the program downloads or
# rebuilds on its own. A cache costs a few seconds to refill; anything else you
# might lose (a login, a setting, an open tab) is not ours to touch.

# --- web browsers (Chrome, Chromium, Brave, Edge) -----------------------------
#
# Every Chromium-based browser uses the same layout, so one routine covers them
# all. For each browser in $VS_CLEAN_BROWSERS (a folder name under ~/.config and
# ~/.cache), and ONLY while that browser is closed:
#
# Deleted - all of it is rebuilt or downloaded again when needed:
#   ~/.cache/<browser>/                the page cache (Cache, Code Cache)
#   <profile>/GPUCache, Dawn*Cache     compiled graphics shaders
#   <profile>/Service Worker/CacheStorage, <profile>/WebStorage/*/CacheStorage
#                                      what websites keep for offline use; they
#                                      fetch it again on the next visit
#   GrShaderCache, ShaderCache, GraphiteDawnCache   more compiled shaders
#   component_crx_cache, extensions_crx_cache       installer packages of
#                                      components and extensions that are
#                                      ALREADY installed (kept elsewhere)
#   BrowserMetrics, Crash Reports      usage statistics and crash dumps
#
# Never touched: bookmarks, history, passwords, cookies (so you stay logged in),
# settings, open tabs, extensions and their data, site data (Local Storage,
# IndexedDB), Service Worker registrations and scripts (so site notifications
# keep working), and the installed components themselves (Widevine for video,
# spell check, the models Chrome uses for features).

# _browser_is_running <user-data-dir> : the browser holds a SingletonLock link
# in its folder while it runs, pointing at "<hostname>-<pid>". That is the same
# check the browser itself makes, and it works for any of them. A lock from
# another computer counts as running: we cannot see that process, so we leave it.
_browser_is_running() {
  local lock="$1/SingletonLock" target host pid
  [ -L "$lock" ] || return 1
  target="$(readlink "$lock" 2>/dev/null)" || return 0
  host="${target%-*}"; pid="${target##*-}"
  [ "$host" = "$(hostname 2>/dev/null)" ] || return 0
  kill -0 "$pid" 2>/dev/null
}

# clean_browser_caches [--verbose] : see above. Safe to run at any time.
# Returns 1 if a browser was open and therefore skipped, so the caller can try
# again later.
clean_browser_caches() {
  local verbose=0 b dir cache prof d before after skipped=0
  case "${1:-}" in --verbose) verbose=1;; esac
  [ "${VS_CLEAN_BROWSER:-1}" = 1 ] || return 0

  for b in ${VS_CLEAN_BROWSERS:-}; do
    dir="$HOME/.config/$b"; cache="$HOME/.cache/$b"
    [ -d "$dir" ] || [ -d "$cache" ] || continue
    if _browser_is_running "$dir"; then
      skipped=1
      [ "$verbose" -eq 1 ] && info "$b is open: left alone (close it and run 'devbox clean' again)"
      continue
    fi
    [ "$verbose" -eq 1 ] && before=$(du -skc "$dir" "$cache" 2>/dev/null | tail -1 | cut -f1)

    _vs_empty_dir "$cache"
    for d in GrShaderCache ShaderCache GraphiteDawnCache component_crx_cache \
             extensions_crx_cache BrowserMetrics "Crash Reports/completed" \
             "Crash Reports/pending"; do
      _vs_empty_dir "$dir/$d"
    done
    # Profiles: Default, "Profile 1"... - any folder with a Preferences file.
    for prof in "$dir"/*/; do
      prof="${prof%/}"
      [ -f "$prof/Preferences" ] || continue
      for d in Cache "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache \
               "Service Worker/CacheStorage"; do
        _vs_empty_dir "$prof/$d"
      done
      for d in "$prof"/WebStorage/*/CacheStorage; do _vs_empty_dir "$d"; done
    done

    if [ "$verbose" -eq 1 ]; then
      after=$(du -skc "$dir" "$cache" 2>/dev/null | tail -1 | cut -f1)
      ok "$b caches cleaned: freed $(( (before - after) / 1024 ))M"
    fi
  done
  [ "$skipped" -eq 0 ]
}

# clean_caches [--verbose] : VSCode and the browsers. Returns 1 if something was
# open and part of the work had to wait.
clean_caches() {
  local rc=0
  clean_vscode_caches "${1:-}"
  vscode_is_running && rc=1
  clean_browser_caches "${1:-}" || rc=1
  return "$rc"
}

# auto_clean_caches : clean_caches in the background, at most once every
# $VS_CLEAN_INTERVAL_HRS (0 = never). A run that had to skip something because
# VSCode or a browser was open does not count: it is tried again an hour later.
auto_clean_caches() {
  [ "${VS_CLEAN_INTERVAL_HRS:-24}" -gt 0 ] 2>/dev/null || return 0
  fresh "$VS_STATE_DIR/caches-cleaned" $((VS_CLEAN_INTERVAL_HRS * 60)) && return 0
  fresh "$VS_STATE_DIR/caches-clean-tried" 60 && return 0
  touch_marker caches-clean-tried
  ( clean_caches && touch_marker caches-cleaned ) >>"$(_vs_log_file)" 2>&1 &
}
