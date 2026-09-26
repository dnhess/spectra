#!/usr/bin/env bats
# Tests for spectra how / spectra run host launch

load test_helper/common-setup

setup() {
  _common_setup
}

teardown() {
  _common_teardown
}

@test "how explains that the CLI does not run deliberation" {
  run "$SPECTRA_CLI" how
  assert_success
  assert_output --partial "does not run deliberation"
  assert_output --partial "Claude Code"
  assert_output --partial "deep-design"
  assert_output --partial "decision-board"
  assert_output --partial "Astra"
  assert_output --partial '$spectra'
}

@test "run on Astra installs the Codex skill and prepares a session" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run decision-board --host astra --topic auth-mfa --tier quick
  assert_success
  assert_output --partial "host: astra"
  assert_output --partial '$spectra'
  assert_output --partial "sessions/decision-board/auth-mfa-"
  [[ -L "$HOME/.agents/skills/spectra" ]]
  [[ -f "$HOME/.agents/skills/spectra/SKILL.md" ]]
  refute_output --partial "You are **The Architect**"
  session_dir="$(echo "$output" | awk '/^session_dir:/{print $2; exit}')"
  [[ -n "$session_dir" ]]
  [[ -f "$session_dir/launch.json" ]]
}

@test "run accepts astro as an Astra alias" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run decision-board --host astro --topic auth-mfa
  assert_success
  assert_output --partial "host: astra"
}

@test "run without a skill shows usage and fails" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run
  assert_failure
  assert_output --partial "Usage: spectra run"
}

@test "run without install fails" {
  run "$SPECTRA_CLI" run decision-board
  assert_failure
  assert_output --partial "not installed"
}

@test "run rejects unknown skills" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run not-a-skill
  assert_failure
  assert_output --partial "Unknown skill"
}

@test "run on Claude prepares a session and prints the host prompt" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run decision-board --host claude --topic auth-mfa --tier quick
  assert_success
  assert_output --partial "host: claude"
  assert_output --partial "decision-board"
  assert_output --partial "Use the decision-board skill"
  assert_output --partial "sessions/decision-board/auth-mfa-"
  session_dir="$(echo "$output" | awk '/^session_dir:/{print $2; exit}')"
  [[ -n "$session_dir" ]]
  [[ -f "$session_dir/session-state.md" ]]
  [[ -f "$session_dir/launch.json" ]]
  [[ -f "$session_dir/session.lock" ]]
}

@test "run defaults host to claude" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run peer-review --topic pr-42
  assert_success
  assert_output --partial "host: claude"
}

@test "run on Codex points at the fail-closed adapter instead of full skills" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" run peer-review --host codex
  assert_failure
  assert_output --partial "approval-gated"
  assert_output --partial "fail-closed"
  assert_output --partial "spectra runtime codex"
}
