#!/usr/bin/env bats
# Tests for persona file loading, counts, and format validation

load test_helper/common-setup

setup() {
  _common_setup
}

teardown() {
  _common_teardown
}

# ---------------------------------------------------------------------------
# File counts — anchored to current state
# ---------------------------------------------------------------------------

@test "deep-design has exactly 12 core personas" {
  local count
  count=$(find "$PROJECT_ROOT/deep-design/personas" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 12 ]
}

@test "deep-design has exactly 10 specialist personas" {
  local count
  count=$(find "$PROJECT_ROOT/deep-design/personas/specialists" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 10 ]
}

@test "decision-board has exactly 7 core personas" {
  local count
  count=$(find "$PROJECT_ROOT/decision-board/personas" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 7 ]
}

@test "decision-board has exactly 9 specialist personas" {
  local count
  count=$(find "$PROJECT_ROOT/decision-board/personas/specialists" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 9 ]
}

@test "code-review has exactly 6 core personas" {
  local count
  count=$(find "$PROJECT_ROOT/code-review/personas" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 6 ]
}

@test "code-review has exactly 6 specialist personas" {
  local count
  count=$(find "$PROJECT_ROOT/code-review/personas/specialists" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  [ "$count" -eq 6 ]
}

# ---------------------------------------------------------------------------
# Format validation — all personas across all skills
# ---------------------------------------------------------------------------

@test "all persona files start with 'You are' on line 1" {
  local fail=0
  while IFS= read -r f; do
    line1=$(head -1 "$f")
    if [[ "$line1" != "You are"* ]]; then
      echo "FAIL: $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

@test "all persona files contain a bold title on line 1" {
  local fail=0
  while IFS= read -r f; do
    line1=$(head -1 "$f")
    if ! echo "$line1" | grep -q '\*\*.\+\*\*'; then
      echo "FAIL: $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

@test "all persona files contain a Focus section" {
  local fail=0
  while IFS= read -r f; do
    if ! grep -q '^## Focus' "$f"; then
      echo "FAIL: $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

@test "all persona files contain a Voice section" {
  local fail=0
  while IFS= read -r f; do
    if ! grep -q '^## Voice' "$f"; then
      echo "FAIL: $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

@test "no persona files are empty — all have more than 5 lines" {
  local fail=0
  while IFS= read -r f; do
    local lines
    lines=$(wc -l < "$f" | tr -d ' ')
    if [ "$lines" -le 5 ]; then
      echo "FAIL ($lines lines): $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

@test "all persona filenames use lowercase-hyphenated convention" {
  local fail=0
  while IFS= read -r f; do
    local bn
    bn=$(basename "$f")
    if ! echo "$bn" | grep -qE '^[a-z][a-z0-9-]*\.md$'; then
      echo "FAIL: $f" >&2
      fail=1
    fi
  done < <(find "$PROJECT_ROOT"/{deep-design,decision-board,code-review}/personas -name "*.md")
  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Special cases
# ---------------------------------------------------------------------------

@test "deep-design CEO/Strategist persona has Special Role section" {
  grep -q '^## Special Role' "$PROJECT_ROOT/deep-design/personas/ceo-strategist.md"
}

@test "deep-design CEO/Strategist persona has Hiring Authority section" {
  grep -q '^## Hiring Authority' "$PROJECT_ROOT/deep-design/personas/ceo-strategist.md"
}

@test "decision-board Devil's Advocate persona has Special Behavior section" {
  grep -q '^## Special Behavior' "$PROJECT_ROOT/decision-board/personas/devils-advocate.md"
}
