#!/usr/bin/env bats
# Tests for spectra backup command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "backup list works with empty backups" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" backup list
  assert_success
  assert_output --partial "No backups"
}

@test "backup list shows existing backups" {
  bootstrap_installed_state
  mkdir -p "$SPECTRA_HOME/backups"
  echo '{}' > "$SPECTRA_HOME/backups/settings.json.20240101-120000"

  run "$SPECTRA_CLI" backup list
  assert_success
  assert_output --partial "20240101-120000"
}

@test "backup restore fails with no backups" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" backup restore
  assert_failure
}
