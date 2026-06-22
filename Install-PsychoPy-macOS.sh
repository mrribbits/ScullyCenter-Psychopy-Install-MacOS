#!/usr/bin/env bash
#
# Install-PsychoPy-macOS.sh
# ----------------------------------------------------------------------------
# Simple interactive PsychoPy installer for macOS. Pick one of:
#   1. PsychoPy Studio      (newer Electron app, .dmg)
#   2. PsychoPy Standalone  (classic app, .dmg)
#   3. PsychoPy in Conda    (per-user Miniconda env; installs Miniconda if needed)
# Then pick a version (default: latest). If a matching install already exists,
# you're offered the chance to delete it first.
#
# Run it directly in Terminal (it is interactive):
#     bash Install-PsychoPy-macOS.sh
# ----------------------------------------------------------------------------

set -o pipefail

PY_PREF="3.10"   # preferred Python version (conda env / which Standalone build to pick)

# ---------- logging ----------
if [ -t 1 ]; then
  C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_HDR=$'\033[35m'; C_RST=$'\033[0m'
else
  C_INFO=; C_OK=; C_WARN=; C_ERR=; C_HDR=; C_RST=
fi
info() { printf '%s[*]  %s%s\n' "$C_INFO" "$*" "$C_RST"; }
ok()   { printf '%s[OK] %s%s\n' "$C_OK"   "$*" "$C_RST"; }
warn() { printf '%s[!]  %s%s\n' "$C_WARN" "$*" "$C_RST"; }
die()  { printf '%s[X]  %s%s\n' "$C_ERR"  "$*" "$C_RST"; exit 1; }

# ---------- prompts (prompt text -> stderr so $(...) capture stays clean) ----------
ask_yn() {
  local q="$1" def="${2:-N}" ans hint
  case "$def" in [Yy]) hint="[Y/n]";; *) hint="[y/N]";; esac
  printf '%s %s ' "$q" "$hint" >&2
  read -r ans
  [ -z "$ans" ] && ans="$def"
  case "$ans" in [Yy]*) return 0;; *) return 1;; esac
}

ask_default() {
  local q="$1" def="$2" ans
  printf '%s [%s] ' "$q" "$def" >&2
  read -r ans
  [ -z "$ans" ] && ans="$def"
  printf '%s' "$ans"
}

choose() {
  local q="$1"; shift
  local n=$# i=1 opt sel
  printf '%s%s%s\n' "$C_HDR" "$q" "$C_RST" >&2
  for opt in "$@"; do printf '  [%d] %s\n' "$i" "$opt" >&2; i=$((i + 1)); done
  while :; do
    printf 'Enter 1-%d: ' "$n" >&2
    read -r sel
    case "$sel" in
      ''|*[!0-9]*) ;;
      *) if [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then printf '%s' "$sel"; return 0; fi;;
    esac
  done
}

# ---------- preflight ----------
[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS. On Windows use Install-PsychoPy.ps1."
command -v curl >/dev/null 2>&1 || die "curl is required (it ships with macOS)."
ARCH="$(uname -m)"   # arm64 (Apple Silicon) or x86_64 (Intel)

printf '%s=== PsychoPy macOS installer ===%s\n' "$C_HDR" "$C_RST"
info "Architecture: $ARCH"

# ---------- helpers ----------
safe_delete() {
  local p="$1" base ts
  [ -e "$p" ] || return 0
  base="$(basename "$p")"
  ts="$(date +%Y%m%d-%H%M%S)"
  if mv "$p" "$HOME/.Trash/${base}.removed-$ts" 2>/dev/null; then
    ok "Moved to Trash: $p"; return 0
  fi
  warn "Couldn't move to Trash (permissions); trying 'sudo rm -rf'..."
  if sudo rm -rf "$p"; then ok "Removed $p"; return 0; fi
  warn "Could not remove $p - please remove it manually."; return 1
}

# find_app studio|standalone -> echoes the first matching /Applications/PsychoPy*.app
find_app() {
  local kind="$1" a
  for a in /Applications/PsychoPy*.app; do
    [ -e "$a" ] || continue
    case "$a" in
      *Studio*) [ "$kind" = "studio" ]     && { printf '%s' "$a"; return 0; } ;;
      *)        [ "$kind" = "standalone" ] && { printf '%s' "$a"; return 0; } ;;
    esac
  done
  return 1
}

# resolve_release_dmgs <repo> <version|latest> -> echoes all .dmg asset URLs (one per line)
resolve_release_dmgs() {
  local repo="$1" ver="$2" api json
  if [ "$ver" = "latest" ]; then
    api="https://api.github.com/repos/$repo/releases/latest"
  else
    api="https://api.github.com/repos/$repo/releases/tags/$ver"
  fi
  json="$(curl -fsSL -H 'User-Agent: psychopy-installer' "$api" 2>/dev/null)" || return 1
  printf '%s' "$json" | grep -oE 'https://[^"]*\.dmg'
}

# install_dmg_app <url> -> mounts dmg, copies the .app (or runs the .pkg) into /Applications.
install_dmg_app() {
  local url="$1" dmg mnt app pkg dest
  info "Downloading: $url"
  dmg="/tmp/$(basename "$url")"
  curl -fL -H 'User-Agent: psychopy-installer' -o "$dmg" "$url" || die "Download failed."
  mnt="$(mktemp -d /tmp/psychopy-mnt.XXXXXX)"
  info "Mounting disk image..."
  hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mnt" || die "Could not mount $dmg"
  app="$(/usr/bin/find "$mnt" -maxdepth 2 -name '*.app' 2>/dev/null | head -n 1)"
  pkg="$(/usr/bin/find "$mnt" -maxdepth 2 -name '*.pkg' 2>/dev/null | head -n 1)"
  if [ -n "$app" ]; then
    dest="/Applications/$(basename "$app")"
    info "Installing to $dest ..."
    rm -rf "$dest" 2>/dev/null
    if ! ditto "$app" "$dest" 2>/dev/null; then
      warn "Copying to /Applications needs admin; retrying with sudo..."
      sudo ditto "$app" "$dest" || { hdiutil detach "$mnt" -quiet; die "Install failed."; }
    fi
    xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true   # avoid 'damaged app' Gatekeeper nags
    ok "Installed $dest"
  elif [ -n "$pkg" ]; then
    info "Running installer package (you may be prompted for your password)..."
    sudo installer -pkg "$pkg" -target / || { hdiutil detach "$mnt" -quiet; die "pkg install failed."; }
    ok "Package installed."
  else
    hdiutil detach "$mnt" -quiet
    die "No .app or .pkg found inside the disk image."
  fi
  hdiutil detach "$mnt" -quiet
  rm -f "$dmg"
}

# ---------- conda ----------
CONDA=""
ensure_conda() {
  local c installer url arch
  if command -v conda >/dev/null 2>&1; then CONDA="$(command -v conda)"; return 0; fi
  for c in "$HOME/miniconda3/bin/conda" "$HOME/anaconda3/bin/conda" "$HOME/miniforge3/bin/conda" \
           "/opt/homebrew/bin/conda" "/opt/miniconda3/bin/conda" "/opt/anaconda3/bin/conda"; do
    [ -x "$c" ] && { CONDA="$c"; info "Using existing conda: $CONDA"; return 0; }
  done
  info "conda not found. Installing per-user Miniconda to \$HOME/miniconda3 (no admin)..."
  if [ "$ARCH" = "arm64" ]; then arch="arm64"; else arch="x86_64"; fi
  url="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-${arch}.sh"
  installer="/tmp/miniconda-$arch.sh"
  curl -fL -o "$installer" "$url" || die "Miniconda download failed."
  bash "$installer" -b -p "$HOME/miniconda3" || die "Miniconda install failed."
  rm -f "$installer"
  CONDA="$HOME/miniconda3/bin/conda"
  [ -x "$CONDA" ] || die "conda not found after install."
  ok "Miniconda installed."
}

# ===========================================================================
#  Step 1: choose what to install
# ===========================================================================
SEL="$(choose "What would you like to install?" \
  "PsychoPy Studio (newer Electron app)" \
  "PsychoPy Standalone (classic app)" \
  "PsychoPy in a Conda environment")"

# ===========================================================================
#  Step 2: version
# ===========================================================================
VERSION="$(ask_default "Which version? (e.g. 2026.2.0) - blank for the latest" "latest")"
info "Version: $VERSION"

# ===========================================================================
#  Step 3: check for an existing install, then install
# ===========================================================================
case "$SEL" in
  1)  # ---------- PsychoPy Studio ----------
    existing="$(find_app studio)"
    if [ -n "$existing" ]; then
      warn "Found an existing PsychoPy Studio app: $existing"
      ask_yn "Delete it before installing?" N && safe_delete "$existing"
    fi
    info "Resolving PsychoPy Studio for macOS..."
    # Studio installers live on the psychopy/psychopy releases (asset: PsychoPy_Studio_<ver>.dmg).
    dmgs="$(resolve_release_dmgs "psychopy/psychopy" "$VERSION")" \
      || dmgs="$(resolve_release_dmgs "psychopy/psychopy" "latest")" \
      || die "Could not query PsychoPy releases on GitHub."
    surl="$(printf '%s\n' "$dmgs" | grep -Ei 'Studio' | head -n 1)"
    [ -z "$surl" ] && die "No PsychoPy Studio .dmg in the '$VERSION' release."
    info "Selected: $(basename "$surl")"
    install_dmg_app "$surl"
    echo; ok "Done. Launch PsychoPy Studio from the Applications folder or Spotlight."
    ;;

  2)  # ---------- PsychoPy Standalone ----------
    existing="$(find_app standalone)"
    if [ -n "$existing" ]; then
      warn "Found an existing PsychoPy app: $existing"
      ask_yn "Delete it before installing?" N && safe_delete "$existing"
    fi
    # Asset: StandalonePsychoPy-<ver>-macOS-<arch>-<pyver>.dmg (older releases omit <arch>).
    dmgs="$(resolve_release_dmgs "psychopy/psychopy" "$VERSION")" \
      || die "Could not query the PsychoPy '$VERSION' release on GitHub."
    macdmgs="$(printf '%s\n' "$dmgs" | grep -E 'StandalonePsychoPy.*macOS')"
    [ -z "$macdmgs" ] && die "No macOS Standalone .dmg in the PsychoPy '$VERSION' release."
    if [ "$ARCH" = "arm64" ]; then archpat='arm64'; else archpat='x86_64|x64|intel'; fi
    archdmgs="$(printf '%s\n' "$macdmgs" | grep -Ei "$archpat")"
    [ -z "$archdmgs" ] && archdmgs="$macdmgs"          # older release without arch in the name
    url="$(printf '%s\n' "$archdmgs" | grep -E "[-]${PY_PREF}\.dmg" | head -n 1)"
    [ -z "$url" ] && url="$(printf '%s\n' "$archdmgs" | head -n 1)"
    info "Selected: $(basename "$url")"
    install_dmg_app "$url"
    echo; ok "Done. Launch PsychoPy from the Applications folder or Spotlight."
    ;;

  3)  # ---------- PsychoPy in a Conda environment ----------
    envname="psychopy"
    ensure_conda
    info "conda: $CONDA"
    if "$CONDA" env list | grep -qE "^[[:space:]]*${envname}[[:space:]]"; then
      warn "Found an existing conda env '$envname'."
      if ask_yn "Delete it before installing?" N; then
        "$CONDA" env remove -n "$envname" -y || warn "Could not remove the env."
      else
        info "Reusing the existing env."
      fi
    fi
    if ! "$CONDA" env list | grep -qE "^[[:space:]]*${envname}[[:space:]]"; then
      info "Creating conda env '$envname' (python=$PY_PREF) from conda-forge..."
      # conda-forge + --override-channels avoids the Anaconda default-channel Terms-of-Service
      # gate and commercial licensing; 'pip' is added since conda-forge python omits it.
      "$CONDA" create -n "$envname" -c conda-forge --override-channels "python=$PY_PREF" pip -y \
        || die "conda create failed. If it's a ToS error, run: $CONDA tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main"
    fi
    base="$("$CONDA" info --base)"
    py="$base/envs/$envname/bin/python"
    [ -x "$py" ] || die "env python not found at $py"
    info "Installing PsychoPy (this can take a while; wxPython may build)..."
    "$py" -m pip install --upgrade pip
    if [ "$VERSION" = "latest" ]; then
      "$py" -m pip install --upgrade psychopy || die "PsychoPy install failed."
    else
      "$py" -m pip install "psychopy==$VERSION" || die "PsychoPy $VERSION install failed."
    fi
    info "Enabling 'conda activate' for your shell (conda init)..."
    "$CONDA" init zsh  >/dev/null 2>&1 || true
    "$CONDA" init bash >/dev/null 2>&1 || true
    echo
    ok "Done."
    info "Open a NEW terminal, then:"
    printf '    conda activate %s\n' "$envname"
    printf '    psychopy            # Coder/Builder GUI\n'
    info "Or run a script directly:"
    printf '    "%s" your_experiment.py\n' "$py"
    ;;
esac
