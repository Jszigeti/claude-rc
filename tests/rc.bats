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
