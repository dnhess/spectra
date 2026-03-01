#!/usr/bin/env bats
# Tests for spectra help, version, and basic dispatch

load test_helper/common-setup

setup() {
  _common_setup
}

teardown() {
  _common_teardown
}

@test "help shows usage and lists all commands" {
  run "$SPECTRA_CLI" help
  assert_success
  assert_output --partial "Usage: spectra <command>"
  assert_output --partial "install"
  assert_output --partial "update"
  assert_output --partial "rollback"
  assert_output --partial "uninstall"
  assert_output --partial "link"
  assert_output --partial "unlink"
  assert_output --partial "status"
  assert_output --partial "doctor"
  assert_output --partial "backup"
  assert_output --partial "version"
  assert_output --partial "help"
}

@test "--help flag shows usage" {
  run "$SPECTRA_CLI" --help
  assert_success
  assert_output --partial "Usage: spectra <command>"
}

@test "no arguments shows help" {
  run "$SPECTRA_CLI"
  assert_success
  assert_output --partial "Usage: spectra <command>"
}

@test "version shows version string" {
  run "$SPECTRA_CLI" version
  assert_success
  assert_output --partial "spectra"
}

@test "--version flag shows version string" {
  run "$SPECTRA_CLI" --version
  assert_success
  assert_output --partial "spectra"
}

@test "unknown command shows error and help" {
  run "$SPECTRA_CLI" nonexistent
  assert_failure
  assert_output --partial "Unknown command: nonexistent"
  assert_output --partial "Usage: spectra <command>"
}
