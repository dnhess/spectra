#!/usr/bin/env bats
load test_helper/common-setup

setup() {
  _common_setup
  export METRICS_TOOL="$PROJECT_ROOT/shared/tools/budget-metrics.sh"
  export SPECTRA_SESSION_ROOT="$TEST_TEMP/sessions"
  export SESSION_DIR="$SPECTRA_SESSION_ROOT/deep-design/test-session"
  mkdir -p "$SESSION_DIR"
}

teardown() { _common_teardown; }

@test "init creates a complete zero snapshot" {
  run bash "$METRICS_TOOL" init "$SESSION_DIR"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data == {
    'agent_spawns': 0,
    'model_calls': 0,
    'finalization_model_calls_used': 0,
    'rounds': 0,
    'output_kb': 0,
    'wall_seconds': 0,
}
assert json.load(open('$SESSION_DIR/budget-metrics.json')) == data
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "init is idempotent and preserves valid observations" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null
  bash "$METRICS_TOOL" record "$SESSION_DIR" --add-model-calls 2 >/dev/null

  run bash "$METRICS_TOOL" init "$SESSION_DIR"
  assert_success
  assert_output --partial '"model_calls": 2'
}

@test "record adds counts and advances monotonic gauges" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null

  run bash "$METRICS_TOOL" record "$SESSION_DIR" \
    --add-agent-spawns 3 --add-model-calls 4 --add-rounds 1 \
    --set-output-kb 12.5 --set-wall-seconds 45
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['agent_spawns'] == 3
assert data['model_calls'] == 4
assert data['rounds'] == 1
assert data['output_kb'] == 12.5
assert data['wall_seconds'] == 45.0
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "record counts finalization calls explicitly as a subset of model calls" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null

  run bash "$METRICS_TOOL" record "$SESSION_DIR" \
    --add-model-calls 2 --add-finalization-model-calls 2
  assert_success
  assert_output --partial '"finalization_model_calls_used": 2'

  run bash "$METRICS_TOOL" record "$SESSION_DIR" \
    --add-model-calls 1 --add-finalization-model-calls 2
  assert_failure
  assert_output --partial "cannot exceed add-model-calls"
}

@test "record rejects decreasing output and wall gauges without changing the file" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null
  bash "$METRICS_TOOL" record "$SESSION_DIR" \
    --set-output-kb 20 --set-wall-seconds 60 >/dev/null

  run bash "$METRICS_TOOL" record "$SESSION_DIR" --set-output-kb 10
  assert_failure
  assert_output --partial "output_kb cannot decrease"

  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/budget-metrics.json'))
assert data['output_kb'] == 20.0
assert data['wall_seconds'] == 60.0
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "record rejects non-finite gauges without changing valid JSON" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null

  for value in NaN Infinity -Infinity; do
    run bash "$METRICS_TOOL" record "$SESSION_DIR" --set-output-kb="$value"
    assert_failure
    assert_output --partial "non-negative number"
  done

  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/budget-metrics.json'), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
assert data['output_kb'] == 0
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "init and record fail closed on malformed or missing snapshots" {
  echo '{bad json' > "$SESSION_DIR/budget-metrics.json"

  run bash "$METRICS_TOOL" init "$SESSION_DIR"
  assert_failure
  assert_output --partial "malformed JSON"

  rm "$SESSION_DIR/budget-metrics.json"
  run bash "$METRICS_TOOL" record "$SESSION_DIR" --add-model-calls 1
  assert_failure
  assert_output --partial "not found"
}

@test "updater rejects symlinked metrics and session directories" {
  echo '{}' > "$TEST_TEMP/outside.json"
  ln -s "$TEST_TEMP/outside.json" "$SESSION_DIR/budget-metrics.json"

  run bash "$METRICS_TOOL" init "$SESSION_DIR"
  assert_failure
  assert_output --partial "must not be a symlink"

  local real_session="$SPECTRA_SESSION_ROOT/deep-design/real-session"
  local linked_session="$SPECTRA_SESSION_ROOT/deep-design/linked-session"
  mkdir -p "$real_session"
  ln -s "$real_session" "$linked_session"
  run bash "$METRICS_TOOL" init "$linked_session"
  assert_failure
  assert_output --partial "must not be a symlink"
}

@test "updater confines writes to the configured sessions root" {
  local outside="$TEST_TEMP/outside-session"
  mkdir -p "$outside"

  run bash "$METRICS_TOOL" init "$outside"
  assert_failure
  assert_output --partial "outside the Spectra sessions root"
  [ ! -e "$outside/budget-metrics.json" ]
}

@test "atomic updates leave a valid snapshot and no temporary files" {
  bash "$METRICS_TOOL" init "$SESSION_DIR" >/dev/null
  bash "$METRICS_TOOL" record "$SESSION_DIR" --add-agent-spawns 2 >/dev/null

  run python3 -c "
import json, pathlib
session = pathlib.Path('$SESSION_DIR')
data = json.load(open(session / 'budget-metrics.json'))
assert data['agent_spawns'] == 2
assert list(session.glob('.budget-metrics.*.tmp')) == []
print('OK')
"
  assert_success
  assert_output "OK"
}
