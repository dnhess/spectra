#!/usr/bin/env bats
load test_helper/common-setup

setup() {
  _common_setup
  export REPORT_TOOL="$PROJECT_ROOT/shared/tools/budget-report.py"
  export REPORT_ROOT="$TEST_TEMP/sessions"
  mkdir -p "$REPORT_ROOT"
}

teardown() { _common_teardown; }

make_budgeted_session() {
  local skill="$1" tier="$2" session_id="$3"
  local session_dir="$REPORT_ROOT/$skill/$session_id"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults "$skill" "$tier" \
    > "$session_dir/budget-policy.json"
  python3 -c "
import json
json.dump({
    'agent_spawns': 12,
    'model_calls': 20,
    'rounds': 1,
    'output_kb': 90.0,
    'wall_seconds': 420,
    'finalization_model_calls_used': 2,
}, open('$session_dir/budget-metrics.json', 'w'))
events = [
    {
        'type': 'session_start',
        'session_id': '$session_id',
        'skill': '$skill',
        'tier': '$tier',
        'schema_version': '1.2.0',
    },
    {
        'type': 'context_budget_status',
        'active_threshold': 'warning',
        'controls_active': ['preserve_finalization_reserve'],
        'proposed_action': {'phase': 'discussion', 'allowed': False},
        'metrics': {
            'agents_spawned': 12,
            'model_calls_used': 20,
            'rounds_completed': 1,
            'cumulative_output_kb': 90.0,
            'elapsed_seconds': 420,
        },
    },
    {'type': 'session_end', 'session_id': '$session_id', 'quality': 'Full'},
]
with open('$session_dir/events.jsonl', 'w') as handle:
    for event in events:
        handle.write(json.dumps(event) + '\\n')
"
  echo "$session_dir"
}

@test "report returns an empty JSON result for a missing root" {
  run python3 "$REPORT_TOOL" report "$REPORT_ROOT/missing" --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['totals']['sessions_discovered'] == 0
assert data['sessions'] == []
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize reports planned observed and final budget state" {
  local session_dir
  session_dir="$(make_budgeted_session deep-design standard session-complete)"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['summary_version'] == '1.1.0'
assert data['session_id'] == 'session-complete'
assert data['state'] == 'complete'
assert data['quality'] == 'Full'
assert data['planned']['planned_core_agents'] == 6
assert data['observed']['model_calls'] == 20
assert data['evaluation']['highest_level_seen'] == 'critical'
assert data['outcomes']['blocked_actions_count'] == 1
assert data['outcomes']['controls_activated'] == ['preserve_finalization_reserve']
assert data['outcomes']['finalization_reserve']['usage_known'] is True
assert data['outcomes']['finalization_reserve']['used'] == 2
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize detects critical overshoot and reserve breach" {
  local session_dir
  session_dir="$(make_budgeted_session trust-layer quick session-critical)"
  python3 -c "
import json
path = '$session_dir/budget-metrics.json'
data = json.load(open(path))
data.update({'agent_spawns': 5, 'model_calls': 7, 'rounds': 1, 'output_kb': 60})
json.dump(data, open(path, 'w'))
"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['evaluation']['final_level'] == 'critical'
assert {item['name'] for item in data['outcomes']['overshoot_fields']} >= {
    'agent_spawns', 'model_calls', 'rounds', 'output_kb'
}
assert data['outcomes']['finalization_reserve']['breached'] is True
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize does not infer reserve usage or breach from total calls" {
  local session_dir
  session_dir="$(make_budgeted_session trust-layer quick session-reserve-unknown)"
  python3 -c "
import json
path = '$session_dir/budget-metrics.json'
data = json.load(open(path))
data.pop('finalization_model_calls_used')
data.update({'model_calls': 6})
json.dump(data, open(path, 'w'))
"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
reserve = json.loads(sys.argv[1])['outcomes']['finalization_reserve']
assert reserve['usage_known'] is False
assert reserve['used'] is None
assert reserve['remaining'] is None
assert reserve['encroached'] is True
assert reserve['breached'] is None
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize keeps an event-only session as legacy" {
  local session_dir="$REPORT_ROOT/decision-board/legacy-session"
  mkdir -p "$session_dir"
  python3 -c "
import json
events = [
    {'type': 'session_start', 'session_id': 'legacy-session', 'tier': 'quick'},
    {'type': 'session_end', 'session_id': 'legacy-session', 'quality': 'Partial'},
]
with open('$session_dir/decision-events.jsonl', 'w') as handle:
    for event in events:
        handle.write(json.dumps(event) + '\\n')
"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'legacy'
assert data['quality'] == 'Partial'
assert data['planned'] is None
assert data['compatibility']['legacy_fallback_used'] is True
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize marks malformed policy data invalid without crashing" {
  local session_dir="$REPORT_ROOT/peer-review/malformed-session"
  mkdir -p "$session_dir"
  echo '{bad json' > "$session_dir/budget-policy.json"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'invalid'
assert data['compatibility']['budget_policy_present'] is True
assert data['compatibility']['budget_policy_valid'] is False
assert data['compatibility']['caveats']
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize rejects truncated and non-finite durable metrics" {
  local session_dir="$REPORT_ROOT/peer-review/truncated-metrics"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults peer-review quick \
    > "$session_dir/budget-policy.json"
  echo '{"model_calls":1}' > "$session_dir/budget-metrics.json"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'invalid'
assert data['compatibility']['budget_metrics_valid'] is False
assert any(item['issue'] == 'missing_fields' for item in data['compatibility']['caveats'])
print('OK')
" "$output"
  assert_success
  assert_output "OK"

  echo '{"agent_spawns":0,"model_calls":1,"rounds":0,"output_kb":NaN,"wall_seconds":1}' \
    > "$session_dir/budget-metrics.json"
  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'invalid'
assert data['compatibility']['budget_metrics_valid'] is False
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "summarize refuses symlinked telemetry artifacts" {
  local session_dir="$REPORT_ROOT/peer-review/symlink-session"
  mkdir -p "$session_dir"
  echo '{"secret":"outside"}' > "$TEST_TEMP/outside-policy.json"
  ln -s "$TEST_TEMP/outside-policy.json" "$session_dir/budget-policy.json"

  run python3 "$REPORT_TOOL" summarize "$session_dir"
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'invalid'
assert {'artifact': 'budget-policy.json', 'issue': 'symlink_not_allowed'} in data['compatibility']['caveats']
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "report aggregates sessions and respects skill and limit filters" {
  make_budgeted_session deep-design standard deep-one >/dev/null
  make_budgeted_session peer-review standard peer-one >/dev/null
  make_budgeted_session peer-review deep peer-two >/dev/null

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --skill peer-review --limit 1 --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['filters'] == {'skill': 'peer-review', 'limit': 1}
assert data['totals']['sessions_discovered'] == 2
assert data['totals']['sessions_shown'] == 1
assert len(data['sessions']) == 1
assert data['sessions'][0]['skill'] == 'peer-review'
assert data['observed_totals']['model_calls'] == 40
assert data['totals']['policy_present'] == 2
assert data['totals']['calibration_ready'] == 2
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "report prefers a finalized stored summary over later metric changes" {
  local session_dir
  session_dir="$(make_budgeted_session deep-design standard immutable-session)"
  python3 "$REPORT_TOOL" summarize "$session_dir" --state complete \
    > "$session_dir/budget-summary.json"
  echo '{"agent_spawns":99,"model_calls":99,"rounds":99,"output_kb":999,"wall_seconds":9999}' \
    > "$session_dir/budget-metrics.json"

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
summary = data['sessions'][0]
assert summary['observed']['model_calls'] == 20
assert summary['state'] == 'complete'
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "report excludes policy-only sessions from calibration-ready totals" {
  local session_dir="$REPORT_ROOT/deep-design/policy-only"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults deep-design quick \
    > "$session_dir/budget-policy.json"

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['totals']['sessions_discovered'] == 1
assert data['totals']['policy_present'] == 1
assert data['totals']['calibration_ready'] == 0
assert data['sessions'][0]['state'] == 'active'
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "report isolates a malformed stored summary" {
  local session_dir
  session_dir="$(make_budgeted_session peer-review quick malformed-summary)"
  echo '{"summary_version":"1.0.0","session_id":"malformed-summary","skill":"peer-review","state":"complete","compatibility":{"budget_policy_valid":true},"observed":null,"evaluation":null}' \
    > "$session_dir/budget-summary.json"

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
summary = data['sessions'][0]
assert summary['state'] == 'invalid'
assert any(
    item['artifact'] == 'budget-summary.json'
    for item in summary['compatibility']['caveats']
)
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "text report is concise and labels proxy totals" {
  make_budgeted_session coherence-monitor standard coherence-one >/dev/null

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT"
  assert_success
  assert_output --partial "Spectra Budget"
  assert_output --partial "Sessions: 1 discovered"
  assert_output --partial "Observed: spawns="
  assert_output --partial "Recent sessions:"
  assert_output --partial "coherence-monitor"
}

@test "report rejects invalid skill and non-positive limit" {
  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --skill nope
  assert_failure
  assert_output --partial "invalid choice"

  run python3 "$REPORT_TOOL" report "$REPORT_ROOT" --limit 0
  assert_failure
  assert_output --partial "limit must be a positive integer"
}

@test "summarize rejects a missing session directory" {
  run python3 "$REPORT_TOOL" summarize "$REPORT_ROOT/nope"
  assert_failure
  assert_output --partial "session directory not found"
}

@test "summarize accepts anticipated close state before session_end is appended" {
  local session_dir="$REPORT_ROOT/deep-design/closing-session"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults deep-design quick \
    > "$session_dir/budget-policy.json"
  echo '{"agent_spawns":3,"model_calls":5,"rounds":0,"output_kb":20,"wall_seconds":90}' \
    > "$session_dir/budget-metrics.json"

  run python3 "$REPORT_TOOL" summarize "$session_dir" --state complete --quality Partial
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['state'] == 'complete'
assert data['quality'] == 'Partial'
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "shell wrapper confines reads to the configured sessions root" {
  make_budgeted_session deep-design quick safe-session >/dev/null

  run env SPECTRA_SESSION_ROOT="$REPORT_ROOT" \
    bash "$PROJECT_ROOT/shared/tools/budget-report.sh" report "$REPORT_ROOT" --json
  assert_success
  assert_output --partial '"sessions_discovered": 1'

  mkdir -p "$TEST_TEMP/outside-session"
  run env SPECTRA_SESSION_ROOT="$REPORT_ROOT" \
    bash "$PROJECT_ROOT/shared/tools/budget-report.sh" summarize "$TEST_TEMP/outside-session"
  assert_failure
  assert_output --partial "outside the Spectra sessions root"
}
