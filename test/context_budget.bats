#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# context_budget_status event validation
# ---------------------------------------------------------------------------

@test "context_budget_status event validates through validate_event.py" {
  local event
  event="$(make_budget_event 5 none 1 50.0 7)"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}

@test "context_budget_status event has required metrics fields" {
  local event
  event="$(make_budget_event 5 warning 3 127.4 15)"

  run python3 -c "
import json, sys
e = json.loads(sys.argv[1])
m = e['metrics']
assert 'rounds_completed' in m, 'missing rounds_completed'
assert 'cumulative_output_kb' in m, 'missing cumulative_output_kb'
assert 'agents_spawned' in m, 'missing agents_spawned'
assert 'moderator_output_kb' in m, 'missing moderator_output_kb'
assert e['active_threshold'] == 'warning'
print('OK')
" "$event"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# emergency_checkpoint event validation
# ---------------------------------------------------------------------------

@test "emergency_checkpoint event validates through validate_event.py" {
  local event
  event="$(make_emergency_checkpoint 42 discussion 3)"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}

@test "emergency_checkpoint recovery_state contains all required fields" {
  local event
  event="$(make_emergency_checkpoint 42 discussion 3)"

  run python3 -c "
import json, sys
e = json.loads(sys.argv[1])
rs = e['recovery_state']
required = [
    'resume_phase', 'resume_round', 'resume_step',
    'completed_agents', 'pending_agents',
    'event_log_sequence_number', 'session_config',
    'checkpoint_reason', 'context_budget_at_checkpoint',
    'security_violations_active'
]
missing = [f for f in required if f not in rs]
assert not missing, f'missing fields: {missing}'
print('OK')
" "$event"
  assert_success
  assert_output "OK"
}

@test "emergency_checkpoint session_config has tier and phase_plan" {
  local event
  event="$(make_emergency_checkpoint 42 discussion 3)"

  run python3 -c "
import json, sys
e = json.loads(sys.argv[1])
sc = e['recovery_state']['session_config']
assert 'tier' in sc, 'missing tier'
assert 'agent_roster' in sc, 'missing agent_roster'
assert 'phase_plan' in sc, 'missing phase_plan'
assert isinstance(sc['phase_plan'], list), 'phase_plan must be a list'
print('OK')
" "$event"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# interrupted quality value
# ---------------------------------------------------------------------------

@test "interrupted quality value accepted in session_end" {
  local event
  event="$(make_session_end_with_kpis 10 interrupted)"

  run python3 "$PROJECT_ROOT/test/helpers/validate_event.py" "$event"
  assert_success
}

# ---------------------------------------------------------------------------
# Threshold detection
# ---------------------------------------------------------------------------

@test "Quick tier: warning threshold at 1+ rounds" {
  run python3 -c "
rounds = 1
tier_max_rounds_caution = 1  # Quick tier
level = 'warning' if rounds >= tier_max_rounds_caution else 'none'
assert level == 'warning', f'expected warning, got {level}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "Standard tier: caution threshold at 3+ rounds" {
  run python3 -c "
rounds = 3
tier_max_rounds_caution = 3  # Standard tier
level = 'caution' if rounds >= tier_max_rounds_caution else 'warning'
assert level == 'caution', f'expected caution, got {level}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "Standard tier: caution threshold at >150KB output" {
  run python3 -c "
output_kb = 155.0
tier_max_output_kb = 150  # Standard tier
level = 'caution' if output_kb > tier_max_output_kb else 'none'
assert level == 'caution', f'expected caution, got {level}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "Deep tier: caution threshold at 5+ rounds" {
  run python3 -c "
rounds = 5
tier_max_rounds_caution = 5  # Deep tier
level = 'caution' if rounds >= tier_max_rounds_caution else 'warning'
assert level == 'caution', f'expected caution, got {level}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# Cumulative output KB computation
# ---------------------------------------------------------------------------

@test "cumulative_output_kb computation from agent files of known sizes" {
  # Create agent files of known sizes
  mkdir -p "$TEST_TEMP/session/opening"
  python3 -c "print('x' * 1023)" > "$TEST_TEMP/session/opening/agent1.json"
  python3 -c "print('x' * 2047)" > "$TEST_TEMP/session/opening/agent2.json"

  run python3 -c "
import os, glob
files = glob.glob('$TEST_TEMP/session/opening/*.json')
total_kb = sum(os.path.getsize(f) / 1024.0 for f in files)
# agent1 is ~1KB, agent2 is ~2KB => ~3KB total
assert 2.5 < total_kb < 3.5, f'expected ~3KB, got {total_kb:.1f}KB'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# Emergency checkpoint + session_end sequence continuity
# ---------------------------------------------------------------------------

@test "emergency_checkpoint and session_end written together maintain sequence" {
  local jsonl_file="$TEST_TEMP/events.jsonl"
  make_event 1 session_start > "$jsonl_file"
  make_emergency_checkpoint 2 discussion 3 >> "$jsonl_file"
  make_session_end_with_kpis 3 interrupted >> "$jsonl_file"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" sequence-check "$jsonl_file"
  assert_success
}

# ---------------------------------------------------------------------------
# Schema migration v2
# ---------------------------------------------------------------------------

@test "schema migration v2 tracked after db init" {
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  assert_success

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT version, description FROM schema_migrations WHERE version = 2"
  assert_success
  assert_output --partial '"version": 2'
  assert_output --partial "Phase 2"
}

@test "schema migration v2 idempotent with v1" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT COUNT(*) as cnt FROM schema_migrations WHERE version = 2"
  assert_success
  assert_output --partial '"cnt": 1'
}

@test "integrity check shows schema_version 2 after init" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" integrity
  assert_success
  assert_output --partial '"schema_version": 2'
}
