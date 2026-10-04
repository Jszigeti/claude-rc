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

render_rows() { # draws the screen of choose_folders, whose locals it reads
  local i p
  printf 'rc · install on %s\n↑↓ move · space toggle · enter install · q quit\n\n' "$OS"
  for i in "${!rows[@]}"; do
    p=" "; (( i == cur )) && p="›"
    case ${rows[$i]} in
      more) printf '%s     show %d more\n' "$p" "${#rest[@]}" ;;
      add) printf '%s     add a path\n\n' "$p" ;;
      login) printf '%s [%s] start at login\n' "$p" "$AT_LOGIN" ;;
      *) printf '%s [%s] %-28s %s\n' "$p" "${CHECKED[${rows[$i]}]}" "$(short "${LIST[${rows[$i]}]}")" "${ages[${rows[$i]}]:-}" ;;
    esac
  done
  printf '\nEach checked folder: ~160 MB of RAM.\nClaude can read, edit and run commands in it.\n'
}

choose_folders() { # fills LIST, CHECKED and AT_LOGIN from arrows and space on $TTY, keeps the defaults without one
  local cands=() ages=() rest=() rows=() cur=0 drawn=0 key seq i p e l
  LIST=("$HOME"); CHECKED=(x); ages=(home); AT_LOGIN=x
  while IFS= read -r l; do
    p=${l#*=}
    [[ $p == "$HOME" ]] && continue
    LIST+=("$p"); CHECKED+=(x); ages+=(served)
  done < <(served)
  while IFS=$'\t' read -r e p; do
    [[ $p == "$HOME" ]] && continue
    cands+=("$p"); ages+=("$(age "$e")")
  done < <(candidates)
  for i in "${!cands[@]}"; do
    if (( i < 5 )); then LIST+=("${cands[$i]}"); CHECKED+=(" "); else rest+=("${cands[$i]}"); fi
  done
  { exec 3< "$TTY"; } 2>/dev/null || return 0  # no terminal: keep the defaults
  while :; do
    rows=()  # one entry per selectable row: a folder index, more, add or login
    for i in "${!LIST[@]}"; do rows+=("$i"); done
    (( ${#rest[@]} )) && rows+=(more)
    rows+=(add login)
    (( cur < 0 )) && cur=0
    (( cur >= ${#rows[@]} )) && cur=$(( ${#rows[@]} - 1 ))
    (( drawn )) && printf '\033[%dA\033[J' "$drawn"
    l=$(render_rows)
    printf '%s\n' "$l"
    drawn=$(( $(printf '%s\n' "$l" | wc -l) ))
    IFS= read -rsn1 -u 3 key || key=""
    case $key in
      $'\033')
        IFS= read -rsn2 -u 3 seq || seq=""
        case $seq in "[A") cur=$((cur - 1)) ;; "[B") cur=$((cur + 1)) ;; esac
        ;;
      " ")
        case ${rows[$cur]} in
          more) LIST+=("${rest[@]}"); for p in "${rest[@]}"; do CHECKED+=(" "); done; rest=() ;;
          add)
            printf 'Path: '
            IFS= read -r -u 3 p || p=""
            drawn=$((drawn + 1))
            if p=$(cd "${p/#\~/$HOME}" 2>/dev/null && pwd); then LIST+=("$p"); CHECKED+=(x); ages+=(added); fi
            ;;
          login) if [[ $AT_LOGIN == x ]]; then AT_LOGIN=" "; else AT_LOGIN=x; fi ;;
          *) i=${rows[$cur]}; if [[ ${CHECKED[$i]} == x ]]; then CHECKED[$i]=" "; else CHECKED[$i]=x; fi ;;
        esac
        ;;
      "") break ;;
      q) die "install cancelled" ;;
    esac
  done
  exec 3<&-
}

write_folders() { # keeps the name of a folder already served, names the new ones
  local tmp i p n
  tmp=$(mktemp)
  for i in "${!LIST[@]}"; do
    [[ ${CHECKED[$i]} == x ]] || continue
    p=${LIST[$i]}
    n=$(name_of_path "$p") || n=$(FOLDERS=$tmp free_name "$p")
    echo "$n=$p" >> "$tmp"
  done
  if $DRY; then say "[dry-run] $FOLDERS:"; sed 's/^/  /' "$tmp"; else mkdir -p "$CONF"; mv "$tmp" "$FOLDERS"; fi
}

stop_unchecked() { # a rerun can uncheck a folder: stop its server
  local n
  $DRY && return 0
  for n in $(t ls -F '#S' 2>/dev/null); do path_of "$n" >/dev/null || stop "$n"; done
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
  # shellcheck source=rc
  source "$RC_LOCAL"  # rc's helpers: folders file, names, candidates, ages, tmux
  choose_folders
  write_folders
  stop_unchecked
}

install_all "$@"
