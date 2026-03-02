#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# sequence-check
# ---------------------------------------------------------------------------

@test "sequence-check passes with valid 1..N sequence (3 events)" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
for i in range(1, 4):
    print(json.dumps({'sequence_number': i, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_success
}

@test "sequence-check fails on gap (1,2,4)" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
for i in [1, 2, 4]:
    print(json.dumps({'sequence_number': i, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_failure
  assert_output --partial "expected sequence_number 3, got 4"
}

@test "sequence-check fails when starting at 0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
for i in [0, 1, 2]:
    print(json.dumps({'sequence_number': i, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_failure
  assert_output --partial "expected sequence_number 1, got 0"
}

@test "sequence-check fails on duplicate (1,2,2)" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
for i in [1, 2, 2]:
    print(json.dumps({'sequence_number': i, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_failure
  assert_output --partial "expected sequence_number 3, got 2"
}

@test "sequence-check fails when sequence_number field is missing" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
print(json.dumps({'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_failure
  assert_output --partial "missing sequence_number"
}

@test "sequence-check success message shows correct count" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
for i in range(1, 4):
    print(json.dumps({'sequence_number': i, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_success
  assert_output "OK — 3 events, sequence continuous"
}

@test "sequence-check single event passes" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
print(json.dumps({'sequence_number': 1, 'type': 'agent_complete'}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_success
  assert_output "OK — 1 events, sequence continuous"
}

# ---------------------------------------------------------------------------
# count-type
# ---------------------------------------------------------------------------

@test "count-type returns correct count for present type" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
print(json.dumps({'type': 'review', 'sequence_number': 1}))
print(json.dumps({'type': 'review', 'sequence_number': 2}))
print(json.dumps({'type': 'session_start', 'sequence_number': 3}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" review
  assert_success
  assert_output "2"
}

@test "count-type returns 0 for absent type" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
print(json.dumps({'type': 'session_start', 'sequence_number': 1}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" review
  assert_success
  assert_output "0"
}

@test "count-type counts mixed types correctly" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json
print(json.dumps({'type': 'review', 'sequence_number': 1}))
print(json.dumps({'type': 'stance', 'sequence_number': 2}))
print(json.dumps({'type': 'review', 'sequence_number': 3}))
print(json.dumps({'type': 'challenge', 'sequence_number': 4}))
print(json.dumps({'type': 'review', 'sequence_number': 5}))
" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" review
  assert_success
  assert_output "3"
}

# ---------------------------------------------------------------------------
# query-project
# ---------------------------------------------------------------------------

@test "query-project returns matching entries" {
  local jsonl_file="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "my-app" > "$jsonl_file"
  make_manifest_entry "sess-002" "other-app" >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$jsonl_file" my-app
  assert_success
  assert_output --partial "my-app"
  refute_output --partial "other-app"
}

@test "query-project returns empty for non-matching project" {
  local jsonl_file="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "my-app" > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$jsonl_file" nonexistent
  assert_success
  assert_output ""
}

@test "query-project filters multiple projects returning only matching" {
  local jsonl_file="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "alpha" > "$jsonl_file"
  make_manifest_entry "sess-002" "beta" >> "$jsonl_file"
  make_manifest_entry "sess-003" "alpha" >> "$jsonl_file"
  make_manifest_entry "sess-004" "gamma" >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$jsonl_file" alpha
  assert_success

  # Count the lines — should be exactly 2
  local line_count
  line_count="$(echo "$output" | wc -l | tr -d ' ')"
  [ "$line_count" -eq 2 ]

  assert_output --partial "alpha"
  refute_output --partial "beta"
  refute_output --partial "gamma"
}

# ---------------------------------------------------------------------------
# Schema validation (validate_event.py)
# ---------------------------------------------------------------------------

@test "validate_event: well-formed event passes" {
  local event
  event="$(make_event 1 session_start)"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}

@test "validate_event: missing event_id detected" {
  local event
  event="$(python3 -c "
import json, datetime
print(json.dumps({
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: event_id"
}

@test "validate_event: missing sequence_number detected" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: sequence_number"
}

@test "validate_event: missing schema_version detected" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: schema_version"
}

@test "validate_event: missing session_id detected" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: session_id"
}

@test "validate_event: missing timestamp detected" {
  local event
  event="$(python3 -c "
import json, uuid
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: timestamp"
}

@test "validate_event: missing type detected" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "missing required field: type"
}

@test "validate_event: non-UUID event_id detected" {
  local event
  event="$(python3 -c "
import json, datetime
print(json.dumps({
    'event_id': 'not-a-uuid',
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "event_id is not valid UUID format"
}

@test "validate_event: non-ISO-8601 timestamp detected" {
  local event
  event="$(python3 -c "
import json, uuid
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session-001',
    'timestamp': 'March 1st 2026',
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "timestamp is not ISO-8601 format"
}

@test "validate_event: wrong schema_version detected" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '2.0.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'session_start'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_failure
  assert_output --partial "schema_version must be '1.0.0' or '1.1.0'"
}

@test "validate_event: schema_version 1.1.0 accepted" {
  local event
  event="$(python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.1.0',
    'session_id': 'test-session-001',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'context_budget_status'
}))")"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}

@test "new event types maintain sequence continuity in mixed log" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_event 1 session_start > "$jsonl_file"
  make_event 2 phase_transition >> "$jsonl_file"
  make_budget_event 3 none 1 50.0 7 >> "$jsonl_file"
  make_event 4 agent_complete >> "$jsonl_file"
  make_event 5 checkpoint_written >> "$jsonl_file"
  make_budget_event 6 warning 2 100.0 14 >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_success
}
