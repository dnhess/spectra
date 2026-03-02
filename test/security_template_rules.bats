#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# ---------------------------------------------------------------------------
# Base template security invariants
# ---------------------------------------------------------------------------

@test "base template contains file-read restriction" {
  run grep -c "Do NOT read sensitive system files" \
    "$PROJECT_ROOT/shared/orchestration.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "base template contains WebSearch Guidelines section" {
  run grep -c "## WebSearch Guidelines" \
    "$PROJECT_ROOT/shared/orchestration.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "base template WebSearch Guidelines include provenance tagging" {
  run grep -c "source_url.*retrieved_at" \
    "$PROJECT_ROOT/shared/orchestration.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# Discussion template delimiter markers
# ---------------------------------------------------------------------------

@test "deep-design discussion template contains agent position delimiters" {
  run grep -c "===BEGIN-AGENT-POSITIONS-" \
    "$PROJECT_ROOT/deep-design/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "decision-board discussion template contains agent position delimiters" {
  run grep -c "===BEGIN-AGENT-POSITIONS-" \
    "$PROJECT_ROOT/decision-board/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "decision-board devil's advocate template contains agent stances delimiters" {
  run grep -c "===BEGIN-AGENT-STANCES-" \
    "$PROJECT_ROOT/decision-board/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "code-review discussion template contains review data delimiters" {
  run grep -c "===BEGIN-REVIEW-DATA-" \
    "$PROJECT_ROOT/code-review/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# Code-review WebSearch prohibition
# ---------------------------------------------------------------------------

@test "code-review discussion agents have WebSearch prohibition" {
  run grep -c "Discussion agents do NOT have WebSearch" \
    "$PROJECT_ROOT/code-review/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}
