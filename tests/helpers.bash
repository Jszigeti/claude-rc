setup() {
  HOME=$(mktemp -d /tmp/rc-test.XXXXXX)
  export HOME FAKE_DIR=$HOME/fake RC_PAUSE=1 RC_STAGGER=0 RC_API=file:///dev/null
  export PATH="$BATS_TEST_DIRNAME/fake:$PATH"
  RC="$BATS_TEST_DIRNAME/../rc"
  mkdir -p "$FAKE_DIR"
}

teardown() {
  TMUX_TMPDIR=$HOME/.local/state/rc tmux -L rc kill-server 2>/dev/null || true
  rm -r "$HOME"
}

wait_for() {
  local i
  for i in $(seq 50); do "$@" && return 0; sleep 0.2; done
  return 1
}

launches() { [ "$(cat "$FAKE_DIR/started-$1" 2>/dev/null | wc -l | tr -d ' ')" = "$2" ]; }

enc() { local s=$1; echo "${s//[^A-Za-z0-9]/-}"; }

history() {
  local d
  d="$HOME/.claude/projects/$(enc "$1")"
  mkdir -p "$d"
  touch -t "$2" "$d/session.jsonl"
}
