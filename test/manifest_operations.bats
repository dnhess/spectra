#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; bootstrap_installed_state; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# Base manifest validation
# ---------------------------------------------------------------------------

@test "valid manifest entry is valid JSON" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "standard" "Full")"
  run python3 -c "import json, sys; json.loads(sys.argv[1])" "$entry"
  assert_success
}

@test "missing session_id field detected" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
del obj['session_id']
assert 'session_id' not in obj, 'session_id still present'
print('session_id missing')
" "$entry"
  assert_success
  assert_output "session_id missing"
}

@test "missing timestamp field detected" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
del obj['timestamp']
assert 'timestamp' not in obj, 'timestamp still present'
print('timestamp missing')
" "$entry"
  assert_success
  assert_output "timestamp missing"
}

@test "missing project field detected" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
del obj['project']
assert 'project' not in obj, 'project still present'
print('project missing')
" "$entry"
  assert_success
  assert_output "project missing"
}

@test "missing tier field detected" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
del obj['tier']
assert 'tier' not in obj, 'tier still present'
print('tier missing')
" "$entry"
  assert_success
  assert_output "tier missing"
}

@test "quality enum Full is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "standard" "Full")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['quality'] == 'Full', f'expected Full, got {obj[\"quality\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "quality enum Partial is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "standard" "Partial")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['quality'] == 'Partial', f'expected Partial, got {obj[\"quality\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "quality enum Minimal is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "standard" "Minimal")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['quality'] == 'Minimal', f'expected Minimal, got {obj[\"quality\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "tier enum quick is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "quick" "Full")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['tier'] == 'quick', f'expected quick, got {obj[\"tier\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "tier enum standard is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "standard" "Full")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['tier'] == 'standard', f'expected standard, got {obj[\"tier\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "tier enum deep is valid" {
  local entry
  entry="$(make_manifest_entry "sess-001" "my-project" "deep" "Full")"
  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['tier'] == 'deep', f'expected deep, got {obj[\"tier\"]}'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# query-project (via jsonl-utils.sh)
# ---------------------------------------------------------------------------

@test "query-project returns matching entry" {
  local manifest="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "my-project" > "$manifest"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$manifest" "my-project"
  assert_success
  assert_output --partial "my-project"
}

@test "query-project empty for non-matching project" {
  local manifest="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "my-project" > "$manifest"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$manifest" "other-project"
  assert_success
  assert_output ""
}

@test "query-project multiple projects only matching returned" {
  local manifest="$TEST_TEMP/manifest.jsonl"
  make_manifest_entry "sess-001" "alpha" > "$manifest"
  make_manifest_entry "sess-002" "beta" >> "$manifest"
  make_manifest_entry "sess-003" "alpha" >> "$manifest"

  run bash "$PROJECT_ROOT/shared/tools/jsonl-utils.sh" query-project "$manifest" "alpha"
  assert_success

  # Should have 2 lines (both alpha entries)
  local line_count
  line_count="$(echo "$output" | wc -l | tr -d ' ')"
  [ "$line_count" -eq 2 ]

  # All returned lines should contain alpha
  assert_output --partial "alpha"
  refute_output --partial "beta"
}

# ---------------------------------------------------------------------------
# Domain-specific fields
# ---------------------------------------------------------------------------

@test "deep-design manifest entry with domain fields is valid" {
  local entry
  entry="$(python3 -c "
import json, datetime
base = json.loads('''$(make_manifest_entry "dd-001" "my-project" "deep" "Full")''')
base['document'] = 'docs/design.md'
base['document_type'] = 'technical_architecture'
base['topics_total'] = 4
print(json.dumps(base))
")"

  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['document'] == 'docs/design.md', 'document mismatch'
assert obj['document_type'] == 'technical_architecture', 'document_type mismatch'
assert obj['topics_total'] == 4, 'topics_total mismatch'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "decision-board manifest entry with domain fields is valid" {
  local entry
  entry="$(python3 -c "
import json, datetime
base = json.loads('''$(make_manifest_entry "db-001" "my-project" "standard" "Full")''')
base['decision_question'] = 'Monorepo or polyrepo?'
base['options'] = ['monorepo', 'polyrepo', 'hybrid']
base['consensus_strength'] = 0.78
print(json.dumps(base))
")"

  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['decision_question'] == 'Monorepo or polyrepo?', 'decision_question mismatch'
assert obj['options'] == ['monorepo', 'polyrepo', 'hybrid'], 'options mismatch'
assert obj['consensus_strength'] == 0.78, 'consensus_strength mismatch'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

@test "code-review manifest entry with domain fields is valid" {
  local entry
  entry="$(python3 -c "
import json, datetime
base = json.loads('''$(make_manifest_entry "cr-001" "my-project" "standard" "Full")''')
base['review_target'] = 'src/auth/service.ts'
base['review_mode'] = 'diff'
base['findings_critical'] = 1
base['findings_major'] = 3
base['findings_minor'] = 5
print(json.dumps(base))
")"

  run python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
assert obj['review_target'] == 'src/auth/service.ts', 'review_target mismatch'
assert obj['review_mode'] == 'diff', 'review_mode mismatch'
assert obj['findings_critical'] == 1, 'findings_critical mismatch'
assert obj['findings_major'] == 3, 'findings_major mismatch'
assert obj['findings_minor'] == 5, 'findings_minor mismatch'
print('OK')
" "$entry"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# session_dirname resolution
# ---------------------------------------------------------------------------

@test "session_dirname resolves to correct full path" {
  local dirname="my-topic-20260301"
  local sessions_root="$HOME/.spectra/sessions/deep-design"
  mkdir -p "$sessions_root"

  run python3 -c "
import os, sys
dirname = sys.argv[1]
sessions_root = sys.argv[2]
full_path = os.path.join(sessions_root, dirname)
print(full_path)
" "$dirname" "$sessions_root"
  assert_success
  assert_output "$sessions_root/$dirname"
}
