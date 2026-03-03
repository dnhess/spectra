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
  for skill in deep-design decision-board peer-review; do
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

@test "rollback updates VERSION_FILE from prev-version" {
  bootstrap_installed_state

  # Set current version to 0.3.0
  echo "0.3.0" > "$SPECTRA_HOME/version"

  # Create skills-prev with identifiable content
  mkdir -p "$SPECTRA_HOME/skills-prev/shared"
  touch "$SPECTRA_HOME/skills-prev/shared/orchestration.md"
  for skill in deep-design decision-board peer-review; do
    mkdir -p "$SPECTRA_HOME/skills-prev/$skill/personas"
    touch "$SPECTRA_HOME/skills-prev/$skill/SKILL.md"
  done

  # Write prev-version marker
  echo "0.2.0" > "$SPECTRA_HOME/prev-version"

  run "$SPECTRA_CLI" rollback
  assert_success

  local version
  version="$(cat "$SPECTRA_HOME/version")"
  [[ "$version" == "0.2.0" ]]
}

@test "rollback swaps prev-version marker" {
  bootstrap_installed_state

  echo "0.3.0" > "$SPECTRA_HOME/version"

  mkdir -p "$SPECTRA_HOME/skills-prev/shared"
  touch "$SPECTRA_HOME/skills-prev/shared/orchestration.md"
  for skill in deep-design decision-board peer-review; do
    mkdir -p "$SPECTRA_HOME/skills-prev/$skill/personas"
    touch "$SPECTRA_HOME/skills-prev/$skill/SKILL.md"
  done

  echo "0.2.0" > "$SPECTRA_HOME/prev-version"

  run "$SPECTRA_CLI" rollback
  assert_success

  # prev-version should now hold the version we rolled back FROM
  local prev
  prev="$(cat "$SPECTRA_HOME/prev-version")"
  [[ "$prev" == "0.3.0" ]]
}

@test "double rollback restores original version" {
  bootstrap_installed_state

  echo "0.3.0" > "$SPECTRA_HOME/version"

  mkdir -p "$SPECTRA_HOME/skills-prev/shared"
  touch "$SPECTRA_HOME/skills-prev/shared/orchestration.md"
  for skill in deep-design decision-board peer-review; do
    mkdir -p "$SPECTRA_HOME/skills-prev/$skill/personas"
    touch "$SPECTRA_HOME/skills-prev/$skill/SKILL.md"
  done

  echo "0.2.0" > "$SPECTRA_HOME/prev-version"

  # First rollback: 0.3.0 -> 0.2.0
  run "$SPECTRA_CLI" rollback
  assert_success

  # Second rollback: 0.2.0 -> 0.3.0
  run "$SPECTRA_CLI" rollback
  assert_success

  local version
  version="$(cat "$SPECTRA_HOME/version")"
  [[ "$version" == "0.3.0" ]]
}
