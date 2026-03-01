#!/usr/bin/env bats
# Tests for spectra status command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "status requires installed state" {
  run "$SPECTRA_CLI" status
  assert_failure
}

@test "status shows version and mode" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" status
  assert_success
  assert_output --partial "Version"
  assert_output --partial "Mode"
}

@test "status shows release mode by default" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" status
  assert_success
  assert_output --partial "release"
}

@test "status shows dev mode when linked" {
  bootstrap_installed_state
  echo "dev" > "$SPECTRA_HOME/mode"
  echo "/tmp/repo" > "$SPECTRA_HOME/dev-repo"
  run "$SPECTRA_CLI" status
  assert_success
  assert_output --partial "dev"
}

@test "status shows skill symlink info" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" status
  assert_success
  assert_output --partial "shared"
}
