load helpers

@test "an unknown command prints the usage and fails" {
  run "$RC" nope
  [ "$status" -eq 2 ]
  grep -q "rc add <folder or name>" <<< "$output"
}

@test "name_for: ~ is home, other folders are lowercased with dashes" {
  source "$RC"
  [ "$(name_for "$HOME")" = home ]
  [ "$(name_for "$HOME/.claude")" = claude ]
  [ "$(name_for "$HOME/Jarvi-prod")" = jarvi-prod ]
  [ "$(name_for "/x/Mon Projet.v2")" = mon-projet-v2 ]
}

@test "free_name: a taken name gets a numeric suffix" {
  source "$RC"
  prepare
  echo "api=/a/api" > "$FOLDERS"
  [ "$(free_name /b/api)" = api-2 ]
}

@test "candidates: history and git repos newest first, without served, vanished or private folders" {
  source "$RC"
  prepare
  mkdir -p "$HOME/zz-alpha" "$HOME/My Proj.v2" "$HOME/zz-served" "$HOME/Documents/secret" "$HOME/zz-beta"
  git -C "$HOME/zz-beta" init -q
  git -C "$HOME/zz-beta" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  history "$HOME/zz-alpha" 202601010000
  history "$HOME/My Proj.v2" 202602010000
  history "$HOME/zz-served" 202603010000
  history "$HOME/zz-gone" 202604010000
  history "$HOME/Documents/secret" 202605010000
  echo "zz-served=$HOME/zz-served" > "$FOLDERS"
  run candidates
  [ "$status" -eq 0 ]
  [ "$(cut -f2 <<< "$output")" = "$(printf '%s\n' "$HOME/zz-beta" "$HOME/My Proj.v2" "$HOME/zz-alpha")" ]
}

@test "age and short format ages and paths" {
  source "$RC"
  [ "$(age $(( $(date +%s) - 300 )))" = "5 min ago" ]
  [ "$(age $(( $(date +%s) - 100000 )))" = "yesterday" ]
  [ "$(short "$HOME/zz-a")" = "~/zz-a" ]
  [ "$(short /opt/x)" = "/opt/x" ]
  [ "$(short "${HOME}2/x")" = "${HOME}2/x" ]
}

@test "rc add serves a path longer than the screen and answers its trust prompt" {
  long="$HOME/$(printf 'zz-a-folder-with-a-very-long-name-%.0s' 1 2 3 4 5 6)"
  mkdir -p "$long"
  touch "$FAKE_DIR/ask-trust"
  run "$RC" add "$long"
  [ "$status" -eq 0 ]
  name=$(basename "$long")
  wait_for test -s "$FAKE_DIR/trusted-$name"
  wait_for launches "$name" 1
  grep -qx "$name=$long" "$HOME/.config/rc/folders"
}

@test "rc starts the missing servers and leaves running ones alone" {
  mkdir -p "$HOME/.config/rc" "$HOME/zz-a"
  echo "zz-a=$HOME/zz-a" > "$HOME/.config/rc/folders"
  run "$RC"
  [ "$status" -eq 0 ]
  grep -q "Starting zz-a…" <<< "$output"
  wait_for launches zz-a 1
  run "$RC"
  [ "$status" -eq 0 ]
  sleep 1
  launches zz-a 1
}

@test "rc lists a connected server as ok and suggests candidates" {
  mkdir -p "$HOME/zz-a" "$HOME/zz-b"
  history "$HOME/zz-b" 202601010000
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  sleep 1
  run "$RC"
  grep -Eq "✓ zz-a +~/zz-a +online" <<< "$output"
  grep -Eq "zz-b +~/zz-b +used" <<< "$output"
  grep -q '(use "rc add <name>" to serve one)' <<< "$output"
}

@test "rc add <name> restarts a served folder" {
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  run "$RC" add zz-a
  [ "$status" -eq 0 ]
  wait_for launches zz-a 2
}

@test "rc rm stops the server and forgets the folder" {
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  run "$RC" rm zz-a
  [ "$status" -eq 0 ]
  run grep -q zz-a "$HOME/.config/rc/folders"
  [ "$status" -eq 1 ]
  run env TMUX_TMPDIR="$HOME/.local/state/rc" tmux -L rc has-session -t =zz-a
  [ "$status" -ne 0 ]
}

@test "rc rm refuses home and unknown names" {
  mkdir -p "$HOME/.config/rc"
  echo "home=$HOME" > "$HOME/.config/rc/folders"
  run "$RC" rm home
  [ "$status" -eq 1 ]
  grep -q home "$HOME/.config/rc/folders"
  run "$RC" rm zz-unknown
  [ "$status" -eq 1 ]
}

@test "a server that exits is started again" {
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  touch "$FAKE_DIR/stop-zz-a"
  wait_for launches zz-a 2
}

@test "an expired login notifies once, waits, then resumes" {
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  touch "$FAKE_DIR/logged-out" "$FAKE_DIR/stop-zz-a"
  wait_for test -e "$HOME/.local/state/rc/login-notified"
  sleep 3
  launches zz-a 1
  [ "$(wc -l < "$FAKE_DIR/notifications" | tr -d ' ')" = 1 ]
  run "$RC"
  grep -q "Claude is logged out" <<< "$output"
  grep -q "claude auth login" <<< "$output"
  rm "$FAKE_DIR/logged-out"
  wait_for launches zz-a 2
  [ ! -e "$HOME/.local/state/rc/login-notified" ]
}

@test "a server that exited is not shown as ok while it waits to restart" {
  export RC_PAUSE=30
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  touch "$FAKE_DIR/stop-zz-a"
  wait_for test ! -e "$FAKE_DIR/stop-zz-a"
  sleep 1
  run "$RC"
  grep -Eq "\- zz-a +~/zz-a +restarting \(1\)" <<< "$output"
}

@test "rc says so when no folder is served yet" {
  run "$RC"
  [ "$status" -eq 0 ]
  grep -q "No folder served yet" <<< "$output"
}

@test "a server waiting on an unknown question says so" {
  mkdir -p "$HOME/zz-a"
  touch "$FAKE_DIR/ask-other"
  "$RC" add "$HOME/zz-a"
  sleep 2
  run "$RC"
  grep -Eq "! zz-a +~/zz-a +waiting for an answer" <<< "$output"
}

@test "rc add takes a bare folder name, in ~ or among recent folders" {
  mkdir -p "$HOME/zz-near" "$HOME/deep/zz-far"
  history "$HOME/deep/zz-far" 202601010000
  cd /
  run "$RC" add zz-near
  [ "$status" -eq 0 ]
  run "$RC" add zz-far
  [ "$status" -eq 0 ]
  grep -qx "zz-near=$HOME/zz-near" "$HOME/.config/rc/folders"
  grep -qx "zz-far=$HOME/deep/zz-far" "$HOME/.config/rc/folders"
  run "$RC" add zz-nowhere
  [ "$status" -eq 1 ]
}

@test "rc rm also takes the folder name or path" {
  mkdir -p "$HOME/Zz-Upper"
  "$RC" add "$HOME/Zz-Upper"
  wait_for launches zz-upper 1
  run "$RC" rm Zz-Upper
  [ "$status" -eq 0 ]
  run grep -q zz-upper "$HOME/.config/rc/folders"
  [ "$status" -eq 1 ]
}

@test "a newly served folder mentions its first session, a restart does not" {
  mkdir -p "$HOME/zz-a"
  run "$RC" add "$HOME/zz-a"
  grep -q "It comes with a first session" <<< "$output"
  wait_for launches zz-a 1
  run "$RC" add zz-a
  run grep -q "It comes with a first session" <<< "$output"
  [ "$status" -eq 1 ]
}

@test "a server offline too long is stopped by a signal before Claude Code gives up" {
  export RC_OFFLINE_LIMIT=1 RC_GUARD_EVERY=0.5
  mkdir -p "$HOME/zz-a"
  "$RC" add "$HOME/zz-a"
  wait_for launches zz-a 1
  touch "$FAKE_DIR/offline-zz-a"
  wait_for test -s "$FAKE_DIR/signals-zz-a"
  wait_for launches zz-a 2
}
