#!/usr/bin/env bats
# Tests for spectra doctor command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "doctor requires installed state" {
  run "$SPECTRA_CLI" doctor
  assert_failure
  assert_output --partial "not installed"
}

@test "doctor reports no issues on healthy install" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" doctor
  assert_success
  assert_output --partial "No issues found"
}

@test "doctor detects missing symlinks" {
  bootstrap_installed_state
  rm "$CLAUDE_SKILLS_DIR/shared"
  run "$SPECTRA_CLI" doctor
  assert_output --partial "not linked"
}

@test "doctor detects broken symlinks" {
  bootstrap_installed_state
  rm -rf "$SPECTRA_HOME/skills/deep-design"
  run "$SPECTRA_CLI" doctor
  assert_output --partial "broken symlink"
}

@test "doctor detects missing permissions" {
  bootstrap_installed_state
  echo '{}' > "$CLAUDE_HOME/settings.json"
  run "$SPECTRA_CLI" doctor
  assert_output --partial "missing"
}

@test "doctor detects missing session directories" {
  bootstrap_installed_state
  rm -rf "$SPECTRA_HOME/sessions/deep-design"
  run "$SPECTRA_CLI" doctor
  assert_output --partial "missing"
}

@test "doctor checks dev mode repo existence" {
  bootstrap_installed_state
  echo "dev" > "$SPECTRA_HOME/mode"
  echo "/tmp/nonexistent-spectra-repo-xyz" > "$SPECTRA_HOME/dev-repo"
  run "$SPECTRA_CLI" doctor
  assert_output --partial "Dev repo missing"
}
