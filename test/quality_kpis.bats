#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# completion_rate
# ---------------------------------------------------------------------------

@test "completion_rate: all agents complete -> 1.0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  # 5 agent_complete events, all with status=completed
  for i in 1 2 3 4 5; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $i,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'agent_complete',
    'agent': 'agent-$i',
    'status': 'completed'
}))" >> "$jsonl_file"
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
completed = sum(1 for e in events if e.get('status') == 'completed')
total = len(events)
rate = completed / total if total > 0 else None
assert rate == 1.0, f'expected 1.0, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "completion_rate: some agents timeout -> 0.6" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  for i in 1 2 3; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $i,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'agent_complete',
    'agent': 'agent-$i',
    'status': 'completed'
}))" >> "$jsonl_file"
  done
  for i in 4 5; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $i,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'agent_complete',
    'agent': 'agent-$i',
    'status': 'timeout'
}))" >> "$jsonl_file"
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
completed = sum(1 for e in events if e.get('status') == 'completed')
total = len(events)
rate = completed / total if total > 0 else None
assert rate == 0.6, f'expected 0.6, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# phase_completion_rate
# ---------------------------------------------------------------------------

@test "phase_completion_rate: all phases -> 1.0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  # 4 phase_transition events out of 4 planned
  for i in 1 2 3 4; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $i,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'phase_transition',
    'from': 'phase_$((i-1))',
    'to': 'phase_$i'
}))" >> "$jsonl_file"
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
transitions = sum(1 for e in events if e['type'] == 'phase_transition')
planned = 4
rate = transitions / planned
assert rate == 1.0, f'expected 1.0, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "phase_completion_rate: interrupted at discussion -> 0.5" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  # 2 phase_transition events out of 4 planned
  for i in 1 2; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $i,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'phase_transition',
    'from': 'phase_$((i-1))',
    'to': 'phase_$i'
}))" >> "$jsonl_file"
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
transitions = sum(1 for e in events if e['type'] == 'phase_transition')
planned = 4
rate = transitions / planned
assert rate == 0.5, f'expected 0.5, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# security_violations_count
# ---------------------------------------------------------------------------

@test "security_violations_count: zero violations -> 0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_event 1 session_start > "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" security_violation
  assert_success
  assert_output "0"
}

@test "security_violations_count: two violations -> 2" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_event 1 security_violation > "$jsonl_file"
  make_event 2 security_violation >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" security_violation
  assert_success
  assert_output "2"
}

# ---------------------------------------------------------------------------
# convergence_rate (deep-design)
# ---------------------------------------------------------------------------

@test "convergence_rate: all topics resolved -> 1.0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  for i in 1 2 3; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $((i * 2 - 1)),
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'topic_created',
    'id': 'T00$i'
}))" >> "$jsonl_file"
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $((i * 2)),
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'topic_resolved',
    'id': 'T00$i',
    'status': 'resolved'
}))" >> "$jsonl_file"
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
created = sum(1 for e in events if e['type'] == 'topic_created')
resolved = sum(1 for e in events if e['type'] == 'topic_resolved' and e.get('status') in ('resolved', 'user_decided'))
rate = resolved / created if created > 0 else None
assert rate == 1.0, f'expected 1.0, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "convergence_rate: mixed resolution -> 0.6" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  # 5 topics created, 3 resolved
  local seq=1
  for i in 1 2 3 4 5; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $seq,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'topic_created',
    'id': 'T00$i'
}))" >> "$jsonl_file"
    seq=$((seq + 1))
  done
  for i in 1 2 3; do
    python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': $seq,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'topic_resolved',
    'id': 'T00$i',
    'status': 'resolved'
}))" >> "$jsonl_file"
    seq=$((seq + 1))
  done

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
created = sum(1 for e in events if e['type'] == 'topic_created')
resolved = sum(1 for e in events if e['type'] == 'topic_resolved' and e.get('status') in ('resolved', 'user_decided'))
rate = resolved / created if created > 0 else None
assert rate == 0.6, f'expected 0.6, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# specialist_utilization (deep-design)
# ---------------------------------------------------------------------------

@test "specialist_utilization: all spawned -> 1.0" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_specialist_recommended 1 hipaa-compliance true true > "$jsonl_file"
  make_specialist_recommended 2 pci-dss true true >> "$jsonl_file"

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
total = len(events)
spawned = sum(1 for e in events if e.get('spawned') is True)
rate = spawned / total if total > 0 else None
assert rate == 1.0, f'expected 1.0, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "specialist_utilization: user declined one -> 0.5" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_specialist_recommended 1 hipaa-compliance true true > "$jsonl_file"
  make_specialist_recommended 2 pci-dss false false >> "$jsonl_file"

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
total = len(events)
spawned = sum(1 for e in events if e.get('spawned') is True)
rate = spawned / total if total > 0 else None
assert rate == 0.5, f'expected 0.5, got {rate}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# concessions_count (decision-board)
# ---------------------------------------------------------------------------

@test "concessions_count from event log" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_event 1 concession > "$jsonl_file"
  make_event 2 concession >> "$jsonl_file"
  make_event 3 challenge >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" count-type "$jsonl_file" concession
  assert_success
  assert_output "2"
}

# ---------------------------------------------------------------------------
# consensus_strength (decision-board)
# ---------------------------------------------------------------------------

@test "consensus_strength extraction from consensus_check event" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': 1,
    'schema_version': '1.0.0',
    'session_id': 'test-session',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': 'consensus_check',
    'consensus_strength': 0.78,
    'consensus_option': 'hybrid'
}))" > "$jsonl_file"

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
checks = [e for e in events if e['type'] == 'consensus_check']
strength = checks[-1]['consensus_strength'] if checks else None
assert strength == 0.78, f'expected 0.78, got {strength}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# rounds_debated (decision-board)
# ---------------------------------------------------------------------------

@test "rounds_debated from event log" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  # Challenge events in rounds 1 and 2
  python3 -c "
import json, uuid, datetime
for i, r in enumerate([(1,1),(2,1),(3,2)], 1):
    print(json.dumps({
        'event_id': str(uuid.uuid4()),
        'sequence_number': i,
        'schema_version': '1.0.0',
        'session_id': 'test-session',
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'type': 'challenge',
        'round': r[1]
    }))
" > "$jsonl_file"

  run python3 -c "
import json
events = [json.loads(l) for l in open('$jsonl_file')]
rounds = set(e.get('round') for e in events if e['type'] in ('challenge', 'concession') and e.get('round'))
count = len(rounds)
assert count == 2, f'expected 2 rounds, got {count}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# KPIs stored in SQLite
# ---------------------------------------------------------------------------

@test "KPIs stored in SQLite sessions table" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier, completion_rate, phase_completion_rate, security_violations_count, convergence_rate, specialist_utilization, escalations_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)" \
    "test-001" "deep-design" "standard" "0.857" "1.0" "0" "0.8" "0.5" "1"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT completion_rate, convergence_rate, specialist_utilization FROM sessions WHERE session_id = ?" \
    "test-001"
  assert_success
  assert_output --partial '"completion_rate": 0.857'
  assert_output --partial '"convergence_rate": 0.8'
  assert_output --partial '"specialist_utilization": 0.5'
}

# ---------------------------------------------------------------------------
# specialist_recommended event validation
# ---------------------------------------------------------------------------

@test "specialist_recommended event validates through validate_event.py" {
  local event
  event="$(make_specialist_recommended 3 hipaa-compliance true true)"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}
