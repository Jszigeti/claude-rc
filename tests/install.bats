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
