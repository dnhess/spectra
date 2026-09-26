#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

policy_file() {
  local skill="$1" tier="$2" output_file="$TEST_TEMP/${skill}-${tier}-policy.json"
  bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults "$skill" "$tier" > "$output_file"
  echo "$output_file"
}

metrics_file() {
  local output_file="$TEST_TEMP/metrics.json"
  shift 0
  python3 -c "
import json
print(json.dumps({
    'agent_spawns': $1,
    'model_calls': $2,
    'rounds': $3,
    'output_kb': $4,
    'wall_seconds': $5,
}))
" > "$output_file"
  echo "$output_file"
}

@test "defaults returns a policy for every skill and tier" {
  for skill in deep-design decision-board peer-review trust-layer coherence-monitor; do
    for tier in quick standard deep; do
      run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults "$skill" "$tier"
      assert_success
      assert_output --partial "\"skill\": \"$skill\""
      assert_output --partial "\"tier\": \"$tier\""
      assert_output --partial "\"policy_version\": \"1.0.0\""
    done
  done
}

@test "model routing keeps routine work cheap and frontier work explicit" {
  run python3 -c "
import json
catalog = json.load(open('$PROJECT_ROOT/shared/schemas/budget-policies.json'))
for policy in catalog['policies']:
    routing = policy['model_policy']
    assert 'synthesis' not in routing['cheap_phases']
    assert 'discussion' not in routing['frontier_phases']
    assert 'opening' not in routing['frontier_phases']
    assert 'positioning' not in routing['frontier_phases']
    assert routing['frontier_requires_approval'] is True
    if policy['tier'] in ('standard', 'deep'):
        assert 'synthesis' in routing['frontier_phases']
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "maximum roster and rounds fit every policy ceiling" {
  for skill in deep-design decision-board peer-review trust-layer coherence-monitor; do
    for tier in quick standard deep; do
      local policy core specialists rounds
      policy="$(bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults "$skill" "$tier")"
      core="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["limits"]["max_core_agents"])' "$policy")"
      specialists="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["limits"]["max_specialists"])' "$policy")"
      rounds="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["limits"]["max_rounds"])' "$policy")"
      run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" estimate "$skill" "$tier" "$core" "$specialists" "$rounds"
      assert_success
    done
  done
}

@test "estimate returns dry-run JSON using defaults" {
  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" estimate peer-review standard
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['skill'] == 'peer-review'
assert data['tier'] == 'standard'
assert data['planned_core_agents'] == 5
assert data['planned_rounds'] == 1
assert data['planned_model_calls'] == 21
assert data['reserved_finalization_calls'] == 2
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "estimate accepts explicit core specialists and rounds" {
  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" estimate deep-design standard 6 2 1
  assert_success

  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert data['planned_active_agents'] == 8
assert data['planned_agent_spawns'] == 24
assert data['planned_model_calls'] == 31
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "invalid skill is rejected" {
  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults nope quick
  assert_failure
  assert_output --partial "invalid skill"
}

@test "invalid tier is rejected" {
  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" defaults deep-design huge
  assert_failure
  assert_output --partial "invalid tier"
}

@test "over-limit estimate fails" {
  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" estimate trust-layer quick 4 0 0
  assert_failure
  assert_output --partial "core exceeds max_core_agents"
}

@test "evaluate returns warning action at 60 percent" {
  local policy metrics
  policy="$(policy_file peer-review standard)"
  metrics="$(metrics_file 18 10 0 20 100)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" evaluate "$policy" "$metrics"
  assert_success
  assert_output --partial "\"level\": \"warning\""
  assert_output --partial "\"action\": \"checkpoint_written\""
}

@test "evaluate returns caution action at 80 percent" {
  local policy metrics
  policy="$(policy_file peer-review standard)"
  metrics="$(metrics_file 20 10 0 20 100)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" evaluate "$policy" "$metrics"
  assert_success
  assert_output --partial "\"level\": \"caution\""
  assert_output --partial "\"action\": \"skip_optional\""
}

@test "evaluate returns critical action at hard threshold" {
  local policy metrics
  policy="$(policy_file peer-review standard)"
  metrics="$(metrics_file 30 10 0 20 100)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" evaluate "$policy" "$metrics"
  assert_success
  assert_output --partial "\"level\": \"critical\""
  assert_output --partial "\"action\": \"force_final\""
}

@test "check exits 2 when a hard limit would be crossed" {
  local policy metrics
  policy="$(policy_file trust-layer quick)"
  metrics="$(metrics_file 3 2 0 10 30)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" check "$policy" "$metrics" --add-agent-spawns 2
  [ "$status" -eq 2 ]
  assert_output --partial "\"allowed\": false"
  assert_output --partial "agent_spawns would exceed max_agent_spawns"
}

@test "check exits 2 when finalization reserve would be crossed" {
  local policy metrics
  policy="$(policy_file trust-layer quick)"
  metrics="$(metrics_file 1 4 0 10 30)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" check "$policy" "$metrics" --add-model-calls 1
  [ "$status" -eq 2 ]
  assert_output --partial "\"allowed\": false"
  assert_output --partial "reserved finalization model-call budget would be crossed"
}

@test "check allows finalization to consume its reserved calls" {
  local policy metrics
  policy="$(policy_file trust-layer quick)"
  metrics="$(metrics_file 1 4 0 10 30)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" check "$policy" "$metrics" --add-model-calls 1 --phase synthesis
  assert_success
  assert_output --partial '"allowed": true'
}

@test "check blocks disabled optional phase" {
  local policy metrics
  policy="$(policy_file trust-layer quick)"
  metrics="$(metrics_file 1 1 0 10 30)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" check "$policy" "$metrics" --phase research
  [ "$status" -eq 2 ]
  assert_output --partial "optional phase disabled by policy: research"
}

@test "check allows usage within hard limits and reserve" {
  local policy metrics
  policy="$(policy_file peer-review standard)"
  metrics="$(metrics_file 5 10 0 10 30)"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" check "$policy" "$metrics" --add-model-calls 5 --add-agent-spawns 3 --phase research
  assert_success
  assert_output --partial "\"allowed\": true"
}

@test "malformed policy file is rejected" {
  local bad_policy metrics
  bad_policy="$TEST_TEMP/bad-policy.json"
  metrics="$(metrics_file 1 1 0 10 30)"
  echo '{"skill": "deep-design"}' > "$bad_policy"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" evaluate "$bad_policy" "$metrics"
  assert_failure
  assert_output --partial "policy missing required field"
}

@test "malformed metrics file is rejected" {
  local policy bad_metrics
  policy="$(policy_file deep-design quick)"
  bad_metrics="$TEST_TEMP/bad-metrics.json"
  echo '{"agent_spawns": "many"}' > "$bad_metrics"

  run bash "$PROJECT_ROOT/shared/tools/budget-policy.sh" evaluate "$policy" "$bad_metrics"
  assert_failure
  assert_output --partial "metrics.agent_spawns must be an integer"
}
