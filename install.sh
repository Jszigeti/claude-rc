#!/usr/bin/env bash
# install.sh: installs rc and serves the folders you pick over Claude Code Remote Control.
#   curl -fsSL https://raw.githubusercontent.com/Jszigeti/claude-rc/v0.1.0/install.sh | bash
#   bash install.sh [--dry-run | --uninstall]

VERSION=v0.1.0
SOURCE=${RC_SOURCE:-https://raw.githubusercontent.com/Jszigeti/claude-rc/$VERSION}  # a local folder in tests
TTY=${RC_TTY:-/dev/tty}  # with curl | bash, stdin is the script itself
BIN=$HOME/.local/bin
LABEL=dev.claude-rc.up
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
UNIT=$HOME/.config/systemd/user/claude-rc.service
DRY=false

say() { printf '%s\n' "$@"; }

die() { printf 'rc: %s\n' "$*" >&2; exit 1; }

act() { if $DRY; then say "[dry-run] $*"; else "$@"; fi; }

write_file() { # file, content
  if $DRY; then say "[dry-run] writes $1"; else mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; fi
}

detect_os() {
  case $(uname -s) in
    Darwin) OS=macos ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        [[ -n ${WSL_INTEROP:-} ]] || die "WSL1 is not supported: switch your distro to WSL2 (wsl --set-version <distro> 2)"
        OS=wsl
      else
        OS=linux
      fi
      ;;
    *) die "native Windows is not supported: install WSL2, then rerun this installer in your distro" ;;
  esac
}

check_claude() {
  local out re='"authMethod": *"claude\.ai"'
  command -v claude >/dev/null || die "Claude Code is missing. Install it: curl -fsSL https://claude.ai/install.sh | bash"
  out=$(claude auth status 2>/dev/null) || true
  [[ $out =~ $re ]] && return 0
  $DRY && { say "[dry-run] claude auth login"; return 0; }
  say "Log Claude Code in with your claude.ai account:"
  claude auth login < "$TTY" > "$TTY" 2>&1 || die "claude.ai login failed"
  out=$(claude auth status 2>/dev/null) || true
  [[ $out =~ $re ]] || die "Remote Control needs a claude.ai account, not an API key"
}

install_packages() {
  local missing=() p
  for p in tmux curl; do command -v "$p" >/dev/null || missing+=("$p"); done
  (( ${#missing[@]} )) || return 0
  if [[ $OS == macos ]]; then
    command -v brew >/dev/null || die "Homebrew is missing. Install it from https://brew.sh, then rerun"
    act brew install "${missing[@]}"
  elif command -v apt-get >/dev/null; then
    act sudo apt-get update -qq
    act sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  elif command -v dnf >/dev/null; then
    act sudo dnf install -y "${missing[@]}"
  else
    die "install ${missing[*]} with your distro's package manager, then rerun"
  fi
}

install_rc() { # sets RC_LOCAL, the rc file whose helpers the installer reuses
  local other
  if $DRY; then
    RC_LOCAL=$SOURCE/rc
    [[ -d $SOURCE ]] || { RC_LOCAL=$(mktemp); curl -fsSL "$SOURCE/rc" -o "$RC_LOCAL"; }
    say "[dry-run] installs rc in $BIN/rc"
  else
    mkdir -p "$BIN"
    if [[ -d $SOURCE ]]; then cp "$SOURCE/rc" "$BIN/rc"; else curl -fsSL "$SOURCE/rc" -o "$BIN/rc"; fi
    chmod 755 "$BIN/rc"
    RC_LOCAL=$BIN/rc
  fi
  case ":$PATH:" in
    *":$BIN:"*) ;;
    *) say "⚠ $BIN is not in your PATH. Add to ~/.zshrc or ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
  other=$(command -v rc || true)
  [[ -z $other || $other == "$BIN/rc" ]] || say "⚠ the rc command also points to $other, which comes first in your PATH"
}

install_all() {
  set -eu
  case ${1:-} in
    "") ;;
    --dry-run) DRY=true ;;
    *) die "usage: install.sh [--dry-run | --uninstall]" ;;
  esac
  detect_os
  check_claude
  install_packages
  install_rc
}

install_all "$@"
