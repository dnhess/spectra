#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "budget requires installed state" {
  run "$SPECTRA_CLI" budget --json
  assert_failure
  assert_output --partial "not installed"
}

@test "budget resolves the report helper from a linked development repository" {
  local repo
  repo="$(create_fake_repo)"
  run "$SPECTRA_CLI" link "$repo"
  assert_success

  run "$SPECTRA_CLI" budget --json
  assert_success
  assert_output --partial '"sessions_discovered": 0'
}

@test "budget returns an empty local report" {
  bootstrap_installed_state

  run "$SPECTRA_CLI" budget --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['report_version'] == '1.0.0'
assert data['totals']['sessions_discovered'] == 0
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "budget calibrate returns recommendation-only output" {
  bootstrap_installed_state

  run "$SPECTRA_CLI" budget calibrate --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['calibration_version'] == '1.0.0'
assert data['mode'] == 'recommendation_only'
assert data['automatic_apply'] is False
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "budget reports a budgeted session and forwards filters" {
  bootstrap_installed_state
  local session_dir="$SPECTRA_HOME/sessions/peer-review/review-session"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults peer-review standard \
    > "$session_dir/budget-policy.json"
  python3 -c "
import json
json.dump({
    'agent_spawns': 8,
    'model_calls': 16,
    'rounds': 0,
    'output_kb': 72.5,
    'wall_seconds': 300,
}, open('$session_dir/budget-metrics.json', 'w'))
with open('$session_dir/review-events.jsonl', 'w') as handle:
    handle.write(json.dumps({
        'type': 'session_start',
        'session_id': 'review-session',
        'skill': 'peer-review',
        'tier': 'standard',
    }) + '\\n')
"

  run "$SPECTRA_CLI" budget --skill peer-review --limit 1 --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['filters'] == {'skill': 'peer-review', 'limit': 1}
assert data['totals']['sessions_discovered'] == 1
assert data['sessions'][0]['session_id'] == 'review-session'
assert data['sessions'][0]['observed']['model_calls'] == 16
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "budget text output contains proxy usage only" {
  bootstrap_installed_state

  run "$SPECTRA_CLI" budget
  assert_success
  assert_output --partial "Spectra Budget"
  assert_output --partial "Observed: spawns="
  refute_output --partial "$"
  refute_output --partial "tokens"
}

@test "budget rejects invalid filters" {
  bootstrap_installed_state

  run "$SPECTRA_CLI" budget --skill shared
  assert_failure
  assert_output --partial "invalid choice"

  run "$SPECTRA_CLI" budget --limit 0
  assert_failure
  assert_output --partial "positive integer"
}
