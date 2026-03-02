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

@test "deep-design discussion template contains round summary delimiters" {
  run grep -c "===BEGIN-ROUND-SUMMARY-" \
    "$PROJECT_ROOT/deep-design/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "decision-board discussion template contains round summary delimiters" {
  run grep -c "===BEGIN-ROUND-SUMMARY-" \
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

# ---------------------------------------------------------------------------
# WebSearch Guidelines in skill templates
# ---------------------------------------------------------------------------

@test "deep-design templates contain WebSearch Guidelines" {
  run grep -c "## WebSearch Guidelines" \
    "$PROJECT_ROOT/deep-design/SKILL.md"
  assert_success
  [[ "${output}" -ge 3 ]]
}

@test "decision-board templates contain WebSearch Guidelines" {
  run grep -c "## WebSearch Guidelines" \
    "$PROJECT_ROOT/decision-board/SKILL.md"
  assert_success
  [[ "${output}" -ge 4 ]]
}

@test "code-review templates contain WebSearch Guidelines" {
  run grep -c "## WebSearch Guidelines" \
    "$PROJECT_ROOT/code-review/SKILL.md"
  assert_success
  [[ "${output}" -ge 3 ]]
}

# ---------------------------------------------------------------------------
# Deep-design final position template
# ---------------------------------------------------------------------------

@test "deep-design has Final Position Agent Prompt Template" {
  run grep -c "### Final Position Agent Prompt Template" \
    "$PROJECT_ROOT/deep-design/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# Code-review file-read restriction coverage
# ---------------------------------------------------------------------------

@test "code-review has file-read restriction in 3+ templates" {
  run grep -c "Do NOT read sensitive system files" \
    "$PROJECT_ROOT/code-review/SKILL.md"
  assert_success
  [[ "${output}" -ge 3 ]]
}

@test "code-review discussion template has WebSearch prohibition in Rules" {
  run grep -c "Do NOT use WebSearch" \
    "$PROJECT_ROOT/code-review/SKILL.md"
  assert_success
  [[ "${output}" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# Round summarization protocol references
# ---------------------------------------------------------------------------

@test "all skills reference round-brief.json in discussion section" {
  for skill in deep-design decision-board code-review; do
    run grep -c "round-brief.json" \
      "$PROJECT_ROOT/$skill/SKILL.md"
    assert_success
    [[ "${output}" -ge 1 ]]
  done
}
