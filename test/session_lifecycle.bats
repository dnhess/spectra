#!/usr/bin/env bats
# Tests for session lifecycle: directories, sentinels, checkpoints, handoffs, locks

load test_helper/common-setup

setup() {
  _common_setup
  bootstrap_installed_state
}

teardown() {
  _common_teardown
}

# ── Directory structure ──────────────────────────────────────────────────

@test "create_session_dir creates opening/ subdir" {
  create_session_dir deep-design test-topic
  [ -d "$SESSION_DIR/opening" ]
}

@test "create_session_dir creates discussion/ subdir" {
  create_session_dir deep-design test-topic
  [ -d "$SESSION_DIR/discussion" ]
}

@test "create_session_dir creates final-positions/ subdir" {
  create_session_dir deep-design test-topic
  [ -d "$SESSION_DIR/final-positions" ]
}

@test "event log file can be created in session dir" {
  create_session_dir deep-design test-topic
  local log_file="$SESSION_DIR/events.jsonl"
  make_event 1 session_start test-001 > "$log_file"
  [ -f "$log_file" ]
  run python3 -c "import json; json.loads(open('$log_file').readline())"
  assert_success
}

# ── Sentinel files (.active-{skill}-session) ─────────────────────────────

@test "make_sentinel creates valid JSON" {
  create_session_dir deep-design test-topic
  local sentinel
  sentinel="$(make_sentinel deep-design "$SESSION_DIR" test-001)"
  run python3 -c "import json; json.load(open('$sentinel'))"
  assert_success
}

@test "sentinel has all 4 required fields" {
  create_session_dir deep-design test-topic
  local sentinel
  sentinel="$(make_sentinel deep-design "$SESSION_DIR" test-001)"
  run python3 -c "
import json
data = json.load(open('$sentinel'))
required = {'session_dir', 'session_id', 'skill', 'started_at'}
assert required.issubset(data.keys()), f'missing: {required - set(data.keys())}'
"
  assert_success
}

@test "sentinel with missing field detected" {
  create_session_dir deep-design test-topic
  local sentinel_path="$SPECTRA_HOME/.active-deep-design-session"
  # Write JSON manually with session_id removed
  python3 -c "
import json, datetime
print(json.dumps({
    'session_dir': '$SESSION_DIR',
    'skill': 'deep-design',
    'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat()
}))" > "$sentinel_path"
  run python3 -c "
import json
data = json.load(open('$sentinel_path'))
required = {'session_dir', 'session_id', 'skill', 'started_at'}
missing = required - set(data.keys())
assert not missing, f'missing: {missing}'
"
  assert_failure
  assert_output --partial "session_id"
}

@test "sentinel started_at is valid ISO-8601" {
  create_session_dir deep-design test-topic
  local sentinel
  sentinel="$(make_sentinel deep-design "$SESSION_DIR" test-001)"
  run python3 -c "
import json, datetime
data = json.load(open('$sentinel'))
datetime.datetime.fromisoformat(data['started_at'])
print('valid ISO-8601')
"
  assert_success
  assert_output --partial "valid ISO-8601"
}

# ── Checkpoint files (session-state.md) ──────────────────────────────────

@test "make_checkpoint creates valid checkpoint" {
  create_session_dir deep-design test-topic
  make_checkpoint "$SESSION_DIR" test-001 opening
  run validate_checkpoint "$SESSION_DIR/session-state.md"
  assert_success
}

@test "missing Session section detected in checkpoint" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/session-state.md" <<'EOF'
## Current Phase

opening in progress.

## Recovery Instructions

Resume from phase opening.
EOF
  run validate_checkpoint "$SESSION_DIR/session-state.md"
  assert_failure
  assert_output --partial "## Session"
}

@test "missing Current Phase section detected in checkpoint" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/session-state.md" <<'EOF'
## Session

- **Session ID**: test-001

## Recovery Instructions

Resume from phase opening.
EOF
  run validate_checkpoint "$SESSION_DIR/session-state.md"
  assert_failure
  assert_output --partial "## Current Phase"
}

@test "missing Recovery Instructions section detected in checkpoint" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/session-state.md" <<'EOF'
## Session

- **Session ID**: test-001

## Current Phase

opening in progress.
EOF
  run validate_checkpoint "$SESSION_DIR/session-state.md"
  assert_failure
  assert_output --partial "## Recovery Instructions"
}

@test "extra sections are OK in checkpoint" {
  create_session_dir deep-design test-topic
  make_checkpoint "$SESSION_DIR" test-001 opening
  cat >> "$SESSION_DIR/session-state.md" <<'EOF'

## Extra Notes

Some additional context here.
EOF
  run validate_checkpoint "$SESSION_DIR/session-state.md"
  assert_success
}

# ── Handoff files (handoff.md) ───────────────────────────────────────────

@test "make_handoff creates valid handoff" {
  create_session_dir deep-design test-topic
  make_handoff "$SESSION_DIR" test-001
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_success
}

@test "missing Session section detected in handoff" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/handoff.md" <<'EOF'
## Key Findings

- Finding 1

## Unresolved

- Item 1

## Recommendations

- Rec 1
EOF
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_failure
  assert_output --partial "## Session"
}

@test "missing Key Findings section detected in handoff" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/handoff.md" <<'EOF'
## Session

- **Session ID**: test-001

## Unresolved

- Item 1

## Recommendations

- Rec 1
EOF
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_failure
  assert_output --partial "Key Findings"
}

@test "Debate Outcome accepted as alternative to Key Findings in handoff" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/handoff.md" <<'EOF'
## Session

- **Session ID**: test-001

## Debate Outcome

- Outcome 1

## Unresolved

- Item 1

## Recommendations

- Rec 1
EOF
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_success
}

@test "missing Unresolved section detected in handoff" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/handoff.md" <<'EOF'
## Session

- **Session ID**: test-001

## Key Findings

- Finding 1

## Recommendations

- Rec 1
EOF
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_failure
  assert_output --partial "## Unresolved"
}

@test "missing Recommendations section detected in handoff" {
  create_session_dir deep-design test-topic
  cat > "$SESSION_DIR/handoff.md" <<'EOF'
## Session

- **Session ID**: test-001

## Key Findings

- Finding 1

## Unresolved

- Item 1
EOF
  run validate_handoff "$SESSION_DIR/handoff.md"
  assert_failure
  assert_output --partial "## Recommendations"
}

# ── Session lock files ───────────────────────────────────────────────────

@test "make_lock creates valid JSON" {
  create_session_dir deep-design test-topic
  make_lock "$SESSION_DIR" test-001
  run python3 -c "import json; json.load(open('$SESSION_DIR/session.lock'))"
  assert_success
}

@test "lock has all fields" {
  create_session_dir deep-design test-topic
  make_lock "$SESSION_DIR" test-001
  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/session.lock'))
required = {'session_id', 'tier', 'ttl_minutes', 'locked_at'}
assert required.issubset(data.keys()), f'missing: {required - set(data.keys())}'
"
  assert_success
}

@test "quick tier has TTL 15" {
  create_session_dir deep-design test-topic
  make_lock "$SESSION_DIR" test-001 quick
  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/session.lock'))
assert data['ttl_minutes'] == 15, f'expected 15, got {data[\"ttl_minutes\"]}'
"
  assert_success
}

@test "standard tier has TTL 30" {
  create_session_dir deep-design test-topic
  make_lock "$SESSION_DIR" test-001 standard
  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/session.lock'))
assert data['ttl_minutes'] == 30, f'expected 30, got {data[\"ttl_minutes\"]}'
"
  assert_success
}

@test "deep tier has TTL 60" {
  create_session_dir deep-design test-topic
  make_lock "$SESSION_DIR" test-001 deep
  run python3 -c "
import json
data = json.load(open('$SESSION_DIR/session.lock'))
assert data['ttl_minutes'] == 60, f'expected 60, got {data[\"ttl_minutes\"]}'
"
  assert_success
}
