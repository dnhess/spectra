#!/usr/bin/env bats
# Tests for spectra rollback command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "rollback requires installed state" {
  run "$SPECTRA_CLI" rollback
  assert_failure
}

@test "rollback fails without previous version" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" rollback
  assert_failure
  assert_output --partial "No previous version"
}

@test "rollback swaps skills and skills-prev" {
  bootstrap_installed_state

  # Create a skills-prev directory with identifiable content
  mkdir -p "$SPECTRA_HOME/skills-prev/shared"
  touch "$SPECTRA_HOME/skills-prev/shared/orchestration.md"
  echo "previous-version-marker" > "$SPECTRA_HOME/skills-prev/shared/marker.txt"
  for skill in deep-design decision-board code-review; do
    mkdir -p "$SPECTRA_HOME/skills-prev/$skill/personas"
    touch "$SPECTRA_HOME/skills-prev/$skill/SKILL.md"
  done

  run "$SPECTRA_CLI" rollback
  assert_success

  # Verify the previous version content is now in skills/
  [[ -f "$SPECTRA_HOME/skills/shared/marker.txt" ]]
  local marker
  marker="$(cat "$SPECTRA_HOME/skills/shared/marker.txt")"
  [[ "$marker" == "previous-version-marker" ]]
}
