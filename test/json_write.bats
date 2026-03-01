#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "writes valid JSON to allowed path" {
  mkdir -p "$HOME/.spectra/sessions/deep-design/test-session"
  run bash "$PROJECT_ROOT/bin/json-write.sh" \
    "$HOME/.spectra/sessions/deep-design/test-session/output.json" \
    '{"test": true}'
  assert_success
  [ -f "$HOME/.spectra/sessions/deep-design/test-session/output.json" ]
  run python3 -c "import json, sys; json.load(open(sys.argv[1]))" \
    "$HOME/.spectra/sessions/deep-design/test-session/output.json"
  assert_success
}

@test "rejects write outside allowed paths" {
  run bash "$PROJECT_ROOT/bin/json-write.sh" \
    "$HOME/outside.json" \
    '{"test": true}'
  assert_failure
  assert_output --partial "not allowed"
}

@test "rejects invalid JSON" {
  mkdir -p "$HOME/.spectra/sessions/deep-design/test-session"
  run bash "$PROJECT_ROOT/bin/json-write.sh" \
    "$HOME/.spectra/sessions/deep-design/test-session/output.json" \
    'not-json'
  assert_failure
  assert_output --partial "invalid JSON"
}

@test "reads from stdin when no JSON argument" {
  mkdir -p "$HOME/.spectra/sessions/deep-design/test-session"
  run bash -c 'echo '"'"'{"stdin": true}'"'"' | bash "$1" "$2"' \
    -- "$PROJECT_ROOT/bin/json-write.sh" \
    "$HOME/.spectra/sessions/deep-design/test-session/output.json"
  assert_success
  run cat "$HOME/.spectra/sessions/deep-design/test-session/output.json"
  assert_output --partial "stdin"
}
