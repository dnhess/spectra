#!/usr/bin/env bats
# Tests for spectra link and unlink commands

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

# --- link tests ---

@test "link requires path argument" {
  run "$SPECTRA_CLI" link
  assert_failure
  assert_output --partial "Usage"
}

@test "link rejects nonexistent path" {
  run "$SPECTRA_CLI" link /nonexistent/path
  assert_failure
}

@test "link rejects non-Spectra repo" {
  local empty_dir="$TEST_TEMP/empty-dir"
  mkdir -p "$empty_dir"
  run "$SPECTRA_CLI" link "$empty_dir"
  assert_failure
  assert_output --partial "Not a Spectra repo"
}

@test "link creates symlinks for all known skills" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  for skill in shared deep-design decision-board code-review; do
    local link="$CLAUDE_SKILLS_DIR/$skill"
    [[ -L "$link" ]]
    local target
    target="$(readlink "$link")"
    [[ "$target" == "$repo_dir/$skill" ]]
  done
}

@test "link bootstraps ~/.spectra when not installed" {
  # Do NOT call bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  [[ -d "$SPECTRA_HOME" ]]
  [[ -d "$SPECTRA_HOME/skills" ]]
  [[ -d "$SPECTRA_HOME/sessions" ]]
  [[ -d "$SPECTRA_HOME/bin" ]]
}

@test "link sets dev mode and records repo path" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  local mode
  mode="$(cat "$SPECTRA_HOME/mode")"
  [[ "$mode" == "dev" ]]

  local recorded_repo
  recorded_repo="$(cat "$SPECTRA_HOME/dev-repo")"
  [[ "$recorded_repo" == "$repo_dir" ]]
}

@test "link configures permissions in settings.json" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  [[ -f "$CLAUDE_HOME/settings.json" ]]
  run grep "json-write.sh" "$CLAUDE_HOME/settings.json"
  assert_success
}

@test "link fails if already in dev mode" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_failure
  assert_output --partial "Already in dev mode"
}

# --- unlink tests ---

@test "unlink reverts to release mode" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  # Ensure release skills exist so unlink doesn't try network calls
  for skill in shared deep-design decision-board code-review; do
    mkdir -p "$SPECTRA_HOME/skills/$skill"
  done
  mkdir -p "$SPECTRA_HOME/skills/shared/tools"
  touch "$SPECTRA_HOME/skills/shared/orchestration.md"

  # Link first
  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  # Verify we are in dev mode
  local mode
  mode="$(cat "$SPECTRA_HOME/mode")"
  [[ "$mode" == "dev" ]]

  # Unlink
  run "$SPECTRA_CLI" unlink
  assert_success

  mode="$(cat "$SPECTRA_HOME/mode")"
  [[ "$mode" == "release" ]]
}
