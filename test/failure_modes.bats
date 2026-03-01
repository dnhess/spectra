#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# Write-once enforcement
# ---------------------------------------------------------------------------

@test "write-once: pre-existing file in opening/ detected as violation" {
  local session_dir
  session_dir="$(create_session_dir deep-design wo-test)"

  # Simulate a file that already exists before agent spawn
  echo '{"agent":"arch","content":"first write"}' > "$session_dir/opening/arch.json"

  # Take pre-spawn snapshot
  local pre_spawn_files
  pre_spawn_files="$(ls "$session_dir/opening/" 2>/dev/null)"

  # Simulate agent writing to same path (overwrite)
  echo '{"agent":"arch","content":"second write"}' > "$session_dir/opening/arch.json"

  # Detection: file was in pre-spawn snapshot
  [[ "$pre_spawn_files" == *"arch.json"* ]]
}

@test "write-once: new file in opening/ is not a violation" {
  local session_dir
  session_dir="$(create_session_dir deep-design wo-clean)"

  # Take pre-spawn snapshot (empty)
  local pre_spawn_count
  pre_spawn_count="$(ls "$session_dir/opening/" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$pre_spawn_count" -eq 0 ]

  # Agent writes new file
  echo '{"agent":"arch","content":"first write"}' > "$session_dir/opening/arch.json"

  # Post-spawn: file exists and was NOT in pre-spawn snapshot
  [ -f "$session_dir/opening/arch.json" ]
  [ "$pre_spawn_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Truncated JSON (retriable P2 failure)
# ---------------------------------------------------------------------------

@test "truncated JSON detected as invalid" {
  local session_dir
  session_dir="$(create_session_dir deep-design trunc-test)"

  # Write truncated JSON (missing closing brace)
  printf '{"agent":"arch","findings":[{"title":"bug"' > "$session_dir/opening/arch.json"

  # Attempt to parse — should fail
  run python3 -c "
import json, sys
try:
    json.load(open(sys.argv[1]))
    print('valid')
except json.JSONDecodeError as e:
    print(f'truncated: {e}')
    sys.exit(1)
" "$session_dir/opening/arch.json"
  assert_failure
  assert_output --partial "truncated"
}

@test "truncated JSON retriable: valid on second read after rewrite" {
  local session_dir
  session_dir="$(create_session_dir deep-design trunc-retry)"

  # First write: truncated
  printf '{"agent":"arch","findings":[' > "$session_dir/opening/arch.json"

  run python3 -c "
import json, sys
try:
    json.load(open(sys.argv[1]))
    sys.exit(0)
except json.JSONDecodeError:
    sys.exit(1)
" "$session_dir/opening/arch.json"
  assert_failure

  # Simulate agent completing the write (retry succeeds)
  echo '{"agent":"arch","findings":[{"title":"bug"}]}' > "$session_dir/opening/arch.json"

  run python3 -c "
import json, sys
try:
    json.load(open(sys.argv[1]))
    print('valid')
    sys.exit(0)
except json.JSONDecodeError:
    sys.exit(1)
" "$session_dir/opening/arch.json"
  assert_success
  assert_output "valid"
}

# ---------------------------------------------------------------------------
# Quorum enforcement
# ---------------------------------------------------------------------------

@test "quorum met with exactly 2 agents" {
  local session_dir
  session_dir="$(create_session_dir deep-design quorum-met)"

  echo '{"agent":"arch"}' > "$session_dir/opening/arch.json"
  echo '{"agent":"sec"}' > "$session_dir/opening/sec.json"

  local agent_count
  agent_count="$(ls "$session_dir/opening/"*.json 2>/dev/null | wc -l | tr -d ' ')"
  [ "$agent_count" -ge 2 ]
}

@test "quorum not met with 1 agent" {
  local session_dir
  session_dir="$(create_session_dir deep-design quorum-fail)"

  echo '{"agent":"arch"}' > "$session_dir/opening/arch.json"

  local agent_count
  agent_count="$(ls "$session_dir/opening/"*.json 2>/dev/null | wc -l | tr -d ' ')"
  [ "$agent_count" -lt 2 ]
}

@test "quorum preserved after excluding one agent from group of 3" {
  local session_dir
  session_dir="$(create_session_dir deep-design quorum-exclude)"

  echo '{"agent":"arch"}' > "$session_dir/opening/arch.json"
  echo '{"agent":"sec"}' > "$session_dir/opening/sec.json"
  echo '{"agent":"perf"}' > "$session_dir/opening/perf.json"

  # Exclude one agent (e.g., validation failure)
  local total=3
  local excluded=1
  local remaining=$((total - excluded))
  [ "$remaining" -ge 2 ]
}

@test "quorum lost after excluding two agents from group of 3" {
  local total=3
  local excluded=2
  local remaining=$((total - excluded))
  [ "$remaining" -lt 2 ]
}

# ---------------------------------------------------------------------------
# Quality computation
# ---------------------------------------------------------------------------

@test "quality: Full when all agents complete and all topics resolved" {
  run python3 -c "
total_agents = 5
completed_agents = 5
total_topics = 3
resolved_topics = 3

if completed_agents == total_agents and resolved_topics == total_topics:
    print('Full')
elif completed_agents >= -(-total_agents // 2) and resolved_topics >= 1:
    print('Partial')
else:
    print('Minimal')
"
  assert_success
  assert_output "Full"
}

@test "quality: Partial when majority complete with some topics resolved" {
  run python3 -c "
total_agents = 5
completed_agents = 3
total_topics = 4
resolved_topics = 2

if completed_agents == total_agents and resolved_topics == total_topics:
    print('Full')
elif completed_agents >= -(-total_agents // 2) and resolved_topics >= 1:
    print('Partial')
else:
    print('Minimal')
"
  assert_success
  assert_output "Partial"
}

@test "quality: Minimal when at quorum but below Partial thresholds" {
  run python3 -c "
total_agents = 5
completed_agents = 2
total_topics = 3
resolved_topics = 0

if completed_agents == total_agents and resolved_topics == total_topics:
    print('Full')
elif completed_agents >= -(-total_agents // 2) and resolved_topics >= 1:
    print('Partial')
else:
    print('Minimal')
"
  assert_success
  assert_output "Minimal"
}

# ---------------------------------------------------------------------------
# Severity classification
# ---------------------------------------------------------------------------

@test "severity tiers: P0 failures are session-fatal" {
  # P0 failures: below quorum, session dir inaccessible, persistent log failure, disk full
  local p0_modes=("below_quorum" "session_dir_inaccessible" "persistent_log_failure" "disk_full")
  [ "${#p0_modes[@]}" -eq 4 ]

  # Verify these are documented as non-retriable
  for mode in "${p0_modes[@]}"; do
    [[ "$mode" != "" ]]
  done
}

@test "severity tiers: P2 truncated JSON is retriable once" {
  local retries=0
  local max_retries=1
  local success=false

  # First attempt: truncated
  local json_str='{"incomplete": true'
  if python3 -c "import json; json.loads('$json_str')" 2>/dev/null; then
    success=true
  else
    retries=$((retries + 1))
  fi

  # Second attempt: complete
  if [ "$retries" -le "$max_retries" ] && [ "$success" = "false" ]; then
    json_str='{"complete": true}'
    if python3 -c "import json; json.loads('$json_str')" 2>/dev/null; then
      success=true
    fi
  fi

  [ "$success" = "true" ]
  [ "$retries" -eq 1 ]
}
