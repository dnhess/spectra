#!/usr/bin/env bats

load test_helper/common-setup

setup() {
  _common_setup
  RUNTIME="$PROJECT_ROOT/adapters/codex/codex-runtime.sh"
  FIXTURE="$PROJECT_ROOT/shared/runtime/fixtures/peer-review-quick.plan.json"
}
teardown() { _common_teardown; }

@test "quick peer-review planned workflow validates" {
  run "$RUNTIME" validate "$FIXTURE"
  assert_success
  assert_output --partial '"status": "valid"'
  assert_output --partial '"actions": 3'
}

@test "capabilities response matches its versioned schema shape" {
  run "$RUNTIME" capabilities
  assert_success
  assert_output --partial '"runtime": "codex"'
  assert_output --partial '"execution_enabled": true'
  assert_output --partial '"max_parallelism": 2'
  assert_output --partial '"requires_explicit_execution_profile": true'
  assert_output --partial '"isolates_user_home": true'
  assert_output --partial '"supported_operations"'
  assert_output --partial '"inspect-context"'
}

@test "validation rejects path traversal and network access" {
  local bad="$TEST_TEMP/bad-plan.json"
  python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
plan["actions"][0]["worker"]["output_path"]["path"] = "../escape.json"
plan["actions"][0]["completion"]["path"]["path"] = "../escape.json"
plan["actions"][0]["execution"]["permissions"]["network"] = True
json.dump(plan, open(sys.argv[2], "w"))
PY
  run "$RUNTIME" validate "$bad"
  assert_failure
  assert_output --partial "unsafe"
}

@test "validation rejects boolean budget counters" {
  local bad="$TEST_TEMP/bool-budget.json"
  python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
plan["actions"][0]["budget"]["add_model_calls"] = True
json.dump(plan, open(sys.argv[2], "w"))
PY
  run "$RUNTIME" validate "$bad"
  assert_failure
  assert_output --partial "increment"
}

@test "validation rejects unknown dependencies, cycles, and impossible quorum" {
  local bad="$TEST_TEMP/bad-dag.json"
  python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
plan["actions"][0]["depends_on"] = ["missing"]
json.dump(plan, open(sys.argv[2], "w"))
PY
  run "$RUNTIME" validate "$bad"
  assert_failure
  assert_output --partial "unknown action"

  python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
plan["actions"][0]["depends_on"] = ["review-reliability"]
plan["actions"][1]["depends_on"] = ["review-design"]
json.dump(plan, open(sys.argv[2], "w"))
PY
  run "$RUNTIME" validate "$bad"
  assert_failure
  assert_output --partial "cycle"

  python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
plan["phase"]["join"]["required_successes"] = 4
json.dump(plan, open(sys.argv[2], "w"))
PY
  run "$RUNTIME" validate "$bad"
  assert_failure
  assert_output --partial "quorum"
}

@test "validation rejects symlinked plan input" {
  local linked="$TEST_TEMP/linked-plan.json"
  ln -s "$FIXTURE" "$linked"
  run "$RUNTIME" validate "$linked"
  assert_failure
  assert_output --partial "non-symlink"
}
