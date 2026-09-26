#!/usr/bin/env bats
load test_helper/common-setup

setup() {
  _common_setup
  export REPORT_TOOL="$PROJECT_ROOT/shared/tools/budget-report.py"
  export REPORT_ROOT="$TEST_TEMP/sessions"
  mkdir -p "$REPORT_ROOT"
}

teardown() { _common_teardown; }

make_final_summary() {
  local skill="$1" tier="$2" session_id="$3" model_calls="$4" day_offset="$5"
  local session_dir="$REPORT_ROOT/$skill/$session_id"
  mkdir -p "$session_dir"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults "$skill" "$tier" \
    > "$session_dir/budget-policy.json"
  python3 -c "
import json
json.dump({
  'agent_spawns': 4,
  'model_calls': $model_calls,
  'finalization_model_calls_used': 1,
  'rounds': 0,
  'output_kb': 20.0,
  'wall_seconds': 100.0,
}, open('$session_dir/budget-metrics.json', 'w'))
"
  python3 "$REPORT_TOOL" summarize "$session_dir" --state complete --quality Full \
    > "$session_dir/budget-summary.json"
  python3 -c "
import datetime, json
path = '$session_dir/budget-summary.json'
data = json.load(open(path))
data['generated_at'] = (datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc) + datetime.timedelta(days=$day_offset)).isoformat().replace('+00:00', 'Z')
json.dump(data, open(path, 'w'))
"
}

make_recommendable_bucket() {
  local skill="${1:-deep-design}" tier="${2:-standard}"
  local index
  for index in $(seq 0 19); do
    make_final_summary "$skill" "$tier" "session-$index" "$((10 + index % 3))" "$index"
  done
}

@test "calibrate returns a successful empty recommendation-only report" {
  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['mode'] == 'recommendation_only'
assert data['automatic_apply'] is False
assert data['buckets'] == []
assert data['totals']['sessions_discovered'] == 0
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate treats v1.0 summaries as evidence-only" {
  make_final_summary deep-design standard old-summary 12 0
  python3 -c "
import json
path = '$REPORT_ROOT/deep-design/old-summary/budget-summary.json'
data = json.load(open(path))
data['summary_version'] = '1.0.0'
data.pop('calibration_source')
json.dump(data, open(path, 'w'))
"
  make_final_summary deep-design standard active-summary 12 1
  python3 -c "
import json
path = '$REPORT_ROOT/deep-design/active-summary/budget-summary.json'
data = json.load(open(path))
data['state'] = 'active'
json.dump(data, open(path, 'w'))
"

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['totals']['evidence_only_sessions'] == 1
assert data['totals']['excluded']['state_active'] == 1
bucket = data['buckets'][0]
assert bucket['recommendation_status'] == 'evidence_only'
assert 'missing_calibration_source' in bucket['reasons']
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate requires twenty sessions and a seven-day span" {
  local index
  for index in $(seq 0 18); do
    make_final_summary deep-design standard "small-$index" 12 "$index"
  done

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  run python3 -c "
import json, sys
bucket = json.loads(sys.argv[1])['buckets'][0]
assert bucket['recommendation_status'] == 'insufficient_evidence'
assert 'minimum_eligible_sessions_not_met' in bucket['reasons']
print('OK')
" "$output"
  assert_success
  assert_output "OK"

  rm -rf "$REPORT_ROOT"
  mkdir -p "$REPORT_ROOT"
  for index in $(seq 0 19); do
    make_final_summary deep-design standard "short-span-$index" 12 0
  done

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  run python3 -c "
import json, sys
bucket = json.loads(sys.argv[1])['buckets'][0]
assert bucket['recommendation_status'] == 'insufficient_evidence'
assert 'minimum_observation_span_not_met' in bucket['reasons']
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate excludes incomplete old summaries and inconsistent telemetry" {
  make_final_summary deep-design standard old-active 12 0
  python3 -c "
import json
path = '$REPORT_ROOT/deep-design/old-active/budget-summary.json'
data = json.load(open(path))
data['summary_version'] = '1.0.0'
data.pop('calibration_source')
data['state'] = 'active'
json.dump(data, open(path, 'w'))
"
  make_final_summary deep-design standard no-observed 12 1
  python3 -c "
import json
path = '$REPORT_ROOT/deep-design/no-observed/budget-summary.json'
data = json.load(open(path))
data['observed'] = None
json.dump(data, open(path, 'w'))
"

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['totals']['evidence_only_sessions'] == 0
assert data['totals']['excluded']['state_active'] == 1
assert data['totals']['excluded']['telemetry_not_valid'] == 1
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate produces deterministic statistics and lower-only recommendations" {
  make_recommendable_bucket

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --skill deep-design --tier standard --json
  assert_success
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
bucket = data['buckets'][0]
assert bucket['recommendation_status'] == 'manual_review_required'
assert bucket['confidence'] == 'medium'
calls = bucket['limits']['max_model_calls']
assert (calls['min'], calls['p50'], calls['p90'], calls['p95'], calls['max']) == (10, 11, 12, 12, 12)
assert calls['current'] == 37
assert calls['candidate'] == 25
assert calls['safety_floor'] == 25
assert calls['recommended'] == 25
assert calls['decision'] == 'reduce'
assert bucket['preserved']['automatic_apply'] is False
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate returns evidence-only when the current policy fingerprint differs" {
  make_recommendable_bucket
  python3 -c "
import hashlib, json
for index in range(20):
  path = '$REPORT_ROOT/deep-design/session-%d/budget-summary.json' % index
  data = json.load(open(path))
  snapshot = data['calibration_source']['policy_snapshot']
  snapshot['limits']['max_model_calls'] += 1
  encoded = json.dumps(snapshot, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
  data['calibration_source']['policy_fingerprint'] = 'sha256:' + hashlib.sha256(encoded).hexdigest()
  json.dump(data, open(path, 'w'))
"

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  run python3 -c "
import json, sys
bucket = json.loads(sys.argv[1])['buckets'][0]
assert bucket['recommendation_status'] == 'evidence_only'
assert 'current_policy_fingerprint_mismatch' in bucket['reasons']
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "calibrate rejects symlinked summaries and never mutates the policy catalog" {
  local session_dir="$REPORT_ROOT/deep-design/symlinked"
  mkdir -p "$session_dir"
  echo '{}' > "$TEST_TEMP/outside-summary.json"
  ln -s "$TEST_TEMP/outside-summary.json" "$session_dir/budget-summary.json"
  local catalog="$PROJECT_ROOT/shared/schemas/budget-policies.json"
  local before after
  before="$(shasum -a 256 "$catalog")"

  run python3 "$REPORT_TOOL" calibrate "$REPORT_ROOT" --json
  assert_success
  after="$(shasum -a 256 "$catalog")"
  [ "$before" = "$after" ]
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['totals']['excluded']['symlink_summary'] == 1
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}
