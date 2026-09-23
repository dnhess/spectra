#!/usr/bin/env bats
# Tests for spectra gate — fail a run when an AGENTS.md constraint is violated

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "gate exits 1 when a must-not-contain constraint appears in the file" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
# Notes

## Constraints

- must-not-contain: FORBIDDEN_TOKEN
EOF
  printf 'this file has FORBIDDEN_TOKEN in it\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 1
  assert_output --partial "must-not-contain: FORBIDDEN_TOKEN"
  assert_output --partial "target.txt"
}

@test "gate exits 0 and prints a pass line when the file satisfies every constraint" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
# Notes

## Constraints

- must-not-contain: FORBIDDEN_TOKEN
- must-contain: REQUIRED_TOKEN
EOF
  printf 'this file has REQUIRED_TOKEN and nothing else\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_success
  assert_output --partial "gate: pass"
  refute_output --partial "#"
}

@test "gate exits 2 when AGENTS.md has no constraints" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
# Notes

No enforceable rules in this file.
EOF
  printf 'anything\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 2
  assert_output --partial "no constraints"
}

@test "gate exits 1 when a must-contain constraint is missing from the file" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
## Constraints

- must-contain: REQUIRED_TOKEN
EOF
  printf 'this file is missing the required string\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 1
  assert_output --partial "must-contain: REQUIRED_TOKEN"
  assert_output --partial "target.txt"
}

@test "gate exits 1 and names the hunk when a diff violates must-not-contain" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
## Constraints

- must-not-contain: FORBIDDEN_TOKEN
EOF
  cat > "$repo/change.diff" <<'EOF'
diff --git a/src/app.py b/src/app.py
index 1111111..2222222 100644
--- a/src/app.py
+++ b/src/app.py
@@ -1,2 +1,3 @@
 keep
+FORBIDDEN_TOKEN
 context
EOF

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" --diff "$repo/change.diff"
  assert_failure 1
  assert_output --partial "must-not-contain: FORBIDDEN_TOKEN"
  assert_output --partial "src/app.py"
  assert_output --partial "@@ -1,2 +1,3 @@"
}

@test "gate exits 2 when the Constraints section has no enforceable rules" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
## Constraints

Do not use eval. Be careful.
EOF
  printf 'eval(\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 2
  assert_output --partial "no constraints"
}

@test "gate ignores unmarked rules outside the Constraints section" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
# Notes

must-not-contain: FORBIDDEN_TOKEN

## Other

- must-not-contain: ALSO_FORBIDDEN
EOF
  printf 'FORBIDDEN_TOKEN ALSO_FORBIDDEN\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 2
  assert_output --partial "no constraints"
}

@test "gate enforces a constraint line marked outside the Constraints section" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo"
  cat > "$repo/AGENTS.md" <<'EOF'
# Notes

constraint: must-not-contain: FORBIDDEN_TOKEN
EOF
  printf 'has FORBIDDEN_TOKEN\n' > "$repo/target.txt"

  run "$SPECTRA_CLI" gate --agents "$repo/AGENTS.md" "$repo/target.txt"
  assert_failure 1
  assert_output --partial "must-not-contain: FORBIDDEN_TOKEN"
  assert_output --partial "target.txt"
}

@test "gate finds AGENTS.md by walking up from the file" {
  local repo="$TEST_TEMP/repo"
  mkdir -p "$repo/nested"
  cat > "$repo/AGENTS.md" <<'EOF'
## Constraints

- must-contain: REQUIRED_TOKEN
EOF
  printf 'REQUIRED_TOKEN\n' > "$repo/nested/target.txt"

  run "$SPECTRA_CLI" gate "$repo/nested/target.txt"
  assert_success
  assert_output --partial "gate: pass"
}


