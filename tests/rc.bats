load helpers

@test "an unknown command prints the usage and fails" {
  run "$RC" nope
  [ "$status" -eq 2 ]
  grep -q "rc add <path or name>" <<< "$output"
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

@test "candidates: history first, then git repos, without served, vanished or private folders" {
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
  [ "$(cut -f2 <<< "$output")" = "$(printf '%s\n' "$HOME/My Proj.v2" "$HOME/zz-alpha" "$HOME/zz-beta")" ]
}

@test "age and short format ages and paths" {
  source "$RC"
  [ "$(age $(( $(date +%s) - 300 )))" = "5 min ago" ]
  [ "$(age $(( $(date +%s) - 100000 )))" = "yesterday" ]
  [ "$(short "$HOME/zz-a")" = "~/zz-a" ]
  [ "$(short /opt/x)" = "/opt/x" ]
  [ "$(short "${HOME}2/x")" = "${HOME}2/x" ]
}
