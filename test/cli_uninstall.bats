#!/usr/bin/env bats
# Tests for spectra uninstall command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "uninstall requires installed state" {
  run "$SPECTRA_CLI" uninstall
  assert_failure
  assert_output --partial "not installed"
}

@test "uninstall removes skill symlinks" {
  bootstrap_installed_state

  # Verify symlinks exist before uninstall
  [[ -L "$CLAUDE_SKILLS_DIR/shared" ]]

  echo "n" | "$SPECTRA_CLI" uninstall

  # Verify symlinks are gone
  [[ ! -L "$CLAUDE_SKILLS_DIR/shared" ]]
}

@test "uninstall removes spectra home" {
  bootstrap_installed_state

  # Verify SPECTRA_HOME exists before uninstall
  [[ -d "$SPECTRA_HOME" ]]

  echo "n" | "$SPECTRA_CLI" uninstall

  # Verify SPECTRA_HOME is gone
  [[ ! -d "$SPECTRA_HOME" ]]
}
