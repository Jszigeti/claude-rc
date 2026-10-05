#!/usr/bin/env bash
# install.sh: installs rc and serves the folders you pick over Claude Code Remote Control.
#   curl -fsSL https://github.com/Jszigeti/claude-rc/releases/latest/download/install.sh | bash
#   bash install.sh [--dry-run | --uninstall]

VERSION=v0.1.6
SOURCE=${RC_SOURCE:-https://raw.githubusercontent.com/Jszigeti/claude-rc/$VERSION}  # a local folder in tests
TTY=${RC_TTY:-/dev/tty}  # with curl | bash, stdin is the script itself
BIN=$HOME/.local/bin
LABEL=dev.claude-rc.up
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
UNIT=$HOME/.config/systemd/user/claude-rc.service
DRY=false
NEW=false  # a folder served for the first time comes with a first session

say() { printf '%s\n' "$@"; }

die() { printf 'rc: %s\n' "$*" >&2; exit 1; }

act() { if $DRY; then say "[dry-run] $*"; else "$@"; fi; }

write_file() { # file, content
  if $DRY; then say "[dry-run] writes $1"; else mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; fi
}

detect_os() {
  case $(uname -s) in
    Darwin) OS=macos OS_NAME=macOS WHEN="When this Mac restarts" START_LABEL="Start my servers when I log in" START_HINT="(adds a Login Item)" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        [[ -n ${WSL_INTEROP:-} ]] || die "WSL1 is not supported: switch your distro to WSL2 (wsl --set-version <distro> 2)"
        OS=wsl OS_NAME=WSL WHEN="When Windows restarts" START_LABEL="Start my servers when I log in to Windows" START_HINT="(systemd and a scheduled task)"
      else
        OS=linux OS_NAME=Linux WHEN="When this machine restarts" START_LABEL="Start my servers when it boots" START_HINT="(systemd user service)"
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
  elif command -v pacman >/dev/null; then
    act sudo pacman -S --needed --noconfirm "${missing[@]}"
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
  local i c p
  printf 'rc · install on %s\n\n' "$OS_NAME"
  printf '%s Which folders should the Claude app reach?\n' "$(paint 36 ◆)"
  (( top == 0 )) || printf '      %s\n' "$(paint 2 "↑ $top more")"
  for i in "${!rows[@]}"; do
    if (( i < ${#LIST[@]} )) && (( i < top || i >= top + fit )); then
      (( i != top + fit )) || printf '      %s\n' "$(paint 2 "↓ $(( ${#LIST[@]} - top - fit )) more")"
      continue
    fi
    c="  "; (( i == cur )) && c="$(paint 36 ›) "
    case ${rows[$i]} in
      more) printf '  %s  show %d more\n' "$c" "${#rest[@]}" ;;
      add) printf '  %s+ add a folder…\n\n%s %s\n' "$c" "$(paint 36 ◆)" "$WHEN" ;;
      login) printf '  %s%s %s  %s\n' "$c" "$(box "$AT_LOGIN")" "$START_LABEL" "$(paint 2 "$START_HINT")" ;;
      *)
        p=$(short "${LIST[${rows[$i]}]}")
        (( ${#p} <= 36 )) || p="…${p: -35}"  # a wrapped line breaks the redraw, which counts lines
        printf '  %s%s %-36s %s\n' "$c" "$(box "${CHECKED[${rows[$i]}]}")" "$p" "$(paint 2 "${ages[${rows[$i]}]:-}")"
        ;;
    esac
  done
  printf '\n%s\n%s\n' "$(paint 2 'Claude can read, edit and run commands there.')" \
    "$(paint 2 '↑↓ move · space select · enter confirm · q quit')"
}

box() { if [[ $1 == x ]]; then paint 32 ◼; else printf '◻'; fi; }

summarize() { # what was chosen, once the screen is gone
  local i names=()
  for i in "${!LIST[@]}"; do [[ ${CHECKED[$i]} != x ]] || names+=("$(short "${LIST[$i]}")"); done
  if (( ${#names[@]} )); then say "$(paint 32 ◇) Folders: $(printf '%s, ' "${names[@]}" | sed 's/, $//')"
  else say "$(paint 32 ◇) Folders: none"
  fi
  if [[ $AT_LOGIN == x ]]; then say "$(paint 32 ◇) $START_LABEL: yes"; else say "$(paint 32 ◇) $START_LABEL: no"; fi
}

choose_folders() { # fills LIST, CHECKED and AT_LOGIN from arrows and space on $TTY, keeps the defaults without one
  local cands=() ages=() rest=() rows=() cur=0 drawn=0 top=0 fit=1000 key seq i p e l
  LIST=("$HOME"); CHECKED=(x); ages=("your home folder"); AT_LOGIN=x
  while IFS= read -r l; do
    p=${l#*=}
    [[ $p == "$HOME" ]] && continue
    LIST+=("$p"); CHECKED+=(x); ages+=("served now")
  done < <(served)
  while IFS=$'\t' read -r e p; do
    [[ $p == "$HOME" ]] && continue
    cands+=("$p"); ages+=("used $(age "$e")")
  done < <(candidates)
  for i in "${!cands[@]}"; do
    if (( i < 5 )); then LIST+=("${cands[$i]}"); CHECKED+=(" "); else rest+=("${cands[$i]}"); fi
  done
  { exec 3< "$TTY"; } 2>/dev/null || return 0  # no terminal: keep the defaults
  # bash only reads key by key from its own stdin, which curl | bash fills with the script: set the terminal ourselves
  KEYS=$(stty -g <&3 2>/dev/null) || KEYS=""
  [[ -z $KEYS ]] || { stty -icanon -echo min 1 <&3; trap 'stty "$KEYS" <&3; printf "\033[?25h"' EXIT; }
  printf '\033[?25l'  # no blinking cursor over the list
  while :; do
    rows=()  # one entry per selectable row: a folder index, more, add or login
    for i in "${!LIST[@]}"; do rows+=("$i"); done
    (( ${#rest[@]} )) && rows+=(more)
    rows+=(add login)
    (( cur < 0 )) && cur=0
    (( cur >= ${#rows[@]} )) && cur=$(( ${#rows[@]} - 1 ))
    l=$(stty size <&3 2>/dev/null) && fit=$(( ${l%% *} - 16 ))  # folder rows that fit, read at each key since the window can be resized
    (( fit >= 3 )) || fit=3
    if (( cur < ${#LIST[@]} )); then  # keep the cursor inside the visible slice of folders
      (( cur >= top )) || top=$cur
      (( cur < top + fit )) || top=$(( cur - fit + 1 ))
    fi
    l=$(render_rows)  # built before touching the screen, then written over the old lines: no blank frame
    (( drawn == 0 )) || printf '\033[%dA' "$drawn"
    printf '%s\n' "$l" | sed $'s/$/\033[K/'
    printf '\033[J'
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
            [[ -z $KEYS ]] || stty "$KEYS" <&3
            IFS= read -r -u 3 p || p=""
            [[ -z $KEYS ]] || stty -icanon -echo min 1 <&3
            drawn=$((drawn + 1))
            if p=$(cd "${p/#\~/$HOME}" 2>/dev/null && pwd); then
              for i in "${!LIST[@]}"; do [[ ${LIST[$i]} != "$p" ]] || { CHECKED[$i]=x; p=""; }; done  # already listed: check it
              [[ -z $p ]] || { LIST+=("$p"); CHECKED+=(x); ages+=("just added"); }
            fi
            ;;
          login) if [[ $AT_LOGIN == x ]]; then AT_LOGIN=" "; else AT_LOGIN=x; fi ;;
          *) i=${rows[$cur]}; if [[ ${CHECKED[$i]} == x ]]; then CHECKED[$i]=" "; else CHECKED[$i]=x; fi ;;
        esac
        ;;
      "") break ;;
      q) die "install cancelled" ;;
    esac
  done
  (( drawn == 0 )) || printf '\033[%dA\033[J' "$drawn"  # the summary replaces the screen, as clack does
  [[ -z $KEYS ]] || { stty "$KEYS" <&3; trap - EXIT; }
  printf '\033[?25h'
  exec 3<&-
}

write_folders() { # keeps the name of a folder already served, names the new ones
  local tmp i p n
  tmp=$(mktemp)
  for i in "${!LIST[@]}"; do
    [[ ${CHECKED[$i]} == x ]] || continue
    p=${LIST[$i]}
    n=$(name_of_path "$p") || { n=$(FOLDERS=$tmp free_name "$p"); NEW=true; }
    echo "$n=$p" >> "$tmp"
  done
  if $DRY; then say "[dry-run] $FOLDERS:"; sed 's/^/  /' "$tmp"; else mkdir -p "$CONF"; mv "$tmp" "$FOLDERS"; fi
}

stop_unchecked() { # a rerun can uncheck a folder: stop its server
  local n
  $DRY && return 0
  for n in $(t ls -F '#S' 2>/dev/null); do path_of "$n" >/dev/null || stop "$n"; done
}

service_path() { # launchd and systemd do not read the shell config
  local c d=$BIN
  for c in claude tmux; do d=$d:$(dirname "$(command -v "$c")"); done
  echo "$d:/usr/bin:/bin:/usr/sbin:/sbin"
}

starter_macos() {
  act mkdir -p "$STATE"
  write_file "$PLIST" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN/rc</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(service_path)</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$STATE/up.log</string>
  <key>StandardErrorPath</key><string>$STATE/up.log</string>
</dict>
</plist>"
  act launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  act launchctl bootstrap "gui/$(id -u)" "$PLIST"
}

starter_linux() {
  write_file "$UNIT" "[Unit]
Description=rc: Claude Code Remote Control servers

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=PATH=$(service_path)
Environment=TMUX_TMPDIR=$STATE
ExecStart=$BIN/rc
ExecStop=$(command -v tmux) -L rc kill-server
TimeoutStartSec=300

[Install]
WantedBy=default.target"
  act systemctl --user daemon-reload
  act systemctl --user enable --now claude-rc.service
  act loginctl enable-linger "$(id -un)" 2>/dev/null || say "⚠ linger refused: the servers start at your next login, not at boot"
}

starter_wsl() { # the Windows scheduled task is not exercised in CI
  if [[ ! -d /run/systemd/system ]]; then
    grep -qs '^systemd=true' /etc/wsl.conf || act sudo sh -c 'printf "\n[boot]\nsystemd=true\n" >> /etc/wsl.conf'
    die "systemd is now enabled. In PowerShell: wsl.exe --shutdown, then rerun this installer"
  fi
  starter_linux
  # systemd does not keep WSL alive: a Windows process attached to the distro does (WSL #13416)
  act powershell.exe -NoProfile -Command "Register-ScheduledTask -TaskName claude-rc -Force -Trigger (New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME) -Action (New-ScheduledTaskAction -Execute wsl.exe -Argument '-d $WSL_DISTRO_NAME -e sleep infinity') -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) | Out-Null"
}

remove_starter() {
  [[ ${RC_SKIP_STARTER:-} != 1 ]] || return 0  # tests stay away from the real launchd and systemd
  case $OS in
    macos) act launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; act rm -f "$PLIST" ;;
    *)
      act systemctl --user disable --now claude-rc.service 2>/dev/null || true
      act rm -f "$UNIT"
      [[ $OS != wsl ]] || act powershell.exe -NoProfile -Command "Unregister-ScheduledTask -TaskName claude-rc -Confirm:\$false" 2>/dev/null || true
      ;;
  esac
}

report() {
  $DRY && return 0
  say ""
  "$BIN/rc" || true
  say ""
  if [[ $AT_LOGIN != x ]]; then say "$(paint 33 !) Your servers start only when you type rc."
  elif [[ ${RC_SKIP_STARTER:-} == 1 ]]; then say "starter not installed (RC_SKIP_STARTER=1)"
  elif [[ $OS == macos ]]; then
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then say "$(paint 32 ✓) Login Item added ($LABEL)"
    else say "$(paint 31 ×) Login Item missing: launchctl print gui/$(id -u)/$LABEL"
    fi
  elif systemctl --user is-active --quiet claude-rc.service; then say "$(paint 32 ✓) claude-rc.service enabled"
  else say "$(paint 31 ×) claude-rc.service inactive: journalctl --user -u claude-rc"
  fi
  [[ $OS != wsl ]] || say "$(paint 33 !) To check: close your WSL terminals, wait 2 min, and see whether your folders stay online."
  ! grep -q '=/mnt/' "$FOLDERS" 2>/dev/null || say "$(paint 33 !) A served folder is under /mnt: WSL is slow there, keep your projects in your Linux home folder"
  say "" "Done. Your folders are in the Claude app, Code tab."
  ! $NEW || say "New ones come with a first session: use it, or archive it once and it won't come back."
  say "  rc              see their state" \
    "  rc add <name>   serve another folder"
}

uninstall() {
  remove_starter
  act env TMUX_TMPDIR="$HOME/.local/state/rc" tmux -L rc kill-server 2>/dev/null || true
  act rm -f "$BIN/rc"
  [[ ! -e $HOME/.local/state/rc ]] || act rm -r "$HOME/.local/state/rc"
  say "✓ rc uninstalled. Your folders stay listed in $HOME/.config/rc/folders."
}

install_all() {
  set -eu
  case ${1:-} in
    "") ;;
    --dry-run) DRY=true ;;
    --uninstall) detect_os; uninstall; return 0 ;;
    *) die "usage: install.sh [--dry-run | --uninstall]" ;;
  esac
  detect_os
  check_claude
  install_packages
  install_rc
  # shellcheck source=rc
  source "$RC_LOCAL"  # rc's helpers: folders file, names, candidates, ages, tmux
  choose_folders
  summarize
  write_folders
  stop_unchecked
  if [[ $AT_LOGIN == x ]]; then
    [[ ${RC_SKIP_STARTER:-} == 1 ]] || "starter_$OS"  # tests stay away from the real launchd and systemd
  else
    remove_starter
  fi
  report
}

install_all "$@"
