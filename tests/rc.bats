load helpers

@test "an unknown command prints the usage and fails" {
  run "$RC" nope
  [ "$status" -eq 2 ]
  grep -q "rc add <path or name>" <<< "$output"
}
