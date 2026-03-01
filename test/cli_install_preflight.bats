#!/usr/bin/env bats
# Tests for spectra install pre-flight checks

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "install fails if already installed" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" install
  assert_failure
  assert_output --partial "already installed"
}
