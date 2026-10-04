load helpers

setup_file() { export RC_SOURCE="$BATS_TEST_DIRNAME/.." RC_SKIP_STARTER=1 RC_TTY=/nonexistent; }

@test "--dry-run says what it would do and changes nothing" {
  run bash "$RC_SOURCE/install.sh" --dry-run
  [ "$status" -eq 0 ]
  grep -qF "[dry-run]" <<< "$output"
  [ ! -e "$HOME/.local/bin/rc" ]
  [ ! -e "$HOME/.config/rc/folders" ]
}

@test "an unknown option fails with the usage" {
  run bash "$RC_SOURCE/install.sh" --nope
  [ "$status" -eq 1 ]
  grep -qF -- "--dry-run | --uninstall" <<< "$output"
}

@test "without a terminal only ~ is served" {
  run bash "$RC_SOURCE/install.sh"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/rc" ]
  [ "$(cat "$HOME/.config/rc/folders")" = "home=$HOME" ]
}

@test "arrows and space toggle a candidate and add a path" {
  mkdir -p "$HOME/zz-alpha" "$HOME/zz-other"
  history "$HOME/zz-alpha" 202601010000
  # down, space on zz-alpha, down, space on "add a path", the path, enter
  printf '\033[B \033[B %s\n\n' "$HOME/zz-other" > "$HOME/keys"
  RC_TTY=$HOME/keys run bash "$RC_SOURCE/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/rc/folders")" = "$(printf '%s\n' "home=$HOME" "zz-alpha=$HOME/zz-alpha" "zz-other=$HOME/zz-other")" ]
}

@test "a rerun keeps what is served" {
  mkdir -p "$HOME/.config/rc" "$HOME/zz-a"
  echo "zz-a=$HOME/zz-a" > "$HOME/.config/rc/folders"
  run bash "$RC_SOURCE/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/rc/folders")" = "$(printf '%s\n' "home=$HOME" "zz-a=$HOME/zz-a")" ]
}

@test "the report lists the served folders, and --uninstall keeps the folders file" {
  run bash "$RC_SOURCE/install.sh"
  [ "$status" -eq 0 ]
  grep -q "Open from the Claude app" <<< "$output"
  run bash "$RC_SOURCE/install.sh" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/rc" ]
  [ ! -e "$HOME/.local/state/rc" ]
  [ "$(cat "$HOME/.config/rc/folders")" = "home=$HOME" ]
}

@test "unchecking start at login says how to start by hand" {
  # down twice to "start at login", space, enter
  printf '\033[B\033[B \n' > "$HOME/keys"
  RC_TTY=$HOME/keys run bash "$RC_SOURCE/install.sh"
  [ "$status" -eq 0 ]
  grep -q "run rc after each login" <<< "$output"
}
