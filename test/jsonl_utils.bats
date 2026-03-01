#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "count returns correct count" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"session_start","sequence_number":1}' > "$jsonl_file"
  echo '{"type":"phase_transition","sequence_number":2}' >> "$jsonl_file"
  echo '{"type":"agent_complete","sequence_number":3}' >> "$jsonl_file"
  echo '{"type":"session_complete","sequence_number":4}' >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count "$jsonl_file"
  assert_success
  assert_output "4"
}

@test "read-type filters by event type" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"session_start","sequence_number":1}' > "$jsonl_file"
  echo '{"type":"phase_transition","sequence_number":2}' >> "$jsonl_file"
  echo '{"type":"agent_complete","sequence_number":3}' >> "$jsonl_file"
  echo '{"type":"session_complete","sequence_number":4}' >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" read-type "$jsonl_file" session_start
  assert_success
  assert_output --partial "session_start"
  refute_output --partial "phase_transition"
}

@test "last returns last event" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"session_start","sequence_number":1}' > "$jsonl_file"
  echo '{"type":"phase_transition","sequence_number":2}' >> "$jsonl_file"
  echo '{"type":"agent_complete","sequence_number":3}' >> "$jsonl_file"
  echo '{"type":"session_complete","sequence_number":4}' >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" last "$jsonl_file"
  assert_success
  assert_output --partial "session_complete"
}

@test "validate passes valid JSONL" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"session_start","sequence_number":1}' > "$jsonl_file"
  echo '{"type":"phase_transition","sequence_number":2}' >> "$jsonl_file"
  echo '{"type":"agent_complete","sequence_number":3}' >> "$jsonl_file"
  echo '{"type":"session_complete","sequence_number":4}' >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" validate "$jsonl_file"
  assert_success
  assert_output --partial "OK"
}

@test "validate fails on invalid JSONL" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo "not json" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" validate "$jsonl_file"
  assert_failure
}

@test "has-sentinel finds session_complete" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"session_start","sequence_number":1}' > "$jsonl_file"
  echo '{"type":"phase_transition","sequence_number":2}' >> "$jsonl_file"
  echo '{"type":"agent_complete","sequence_number":3}' >> "$jsonl_file"
  echo '{"type":"session_complete","sequence_number":4}' >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" has-sentinel "$jsonl_file"
  assert_success
}

@test "has-sentinel fails without session_complete" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  echo '{"type":"other"}' > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" has-sentinel "$jsonl_file"
  assert_failure
}
