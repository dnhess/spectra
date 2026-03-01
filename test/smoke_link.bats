#!/usr/bin/env bats
# Tests for post-link health check (verify_link_health)

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "smoke test passes after clean link" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success
  assert_output --partial "Health check passed"
}

@test "smoke test detects broken symlink" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_success

  # Break a symlink by removing its target
  rm -rf "$repo_dir/deep-design"

  run "$SPECTRA_CLI" doctor
  assert_output --partial "broken"
}

@test "smoke test detects missing SKILL.md" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  # Remove SKILL.md before linking
  rm "$repo_dir/deep-design/SKILL.md"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_output --partial "SKILL.md missing"
}

@test "smoke test detects missing orchestration.md" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  # Remove orchestration.md before linking
  rm "$repo_dir/shared/orchestration.md"

  run "$SPECTRA_CLI" link "$repo_dir"
  assert_output --partial "orchestration.md missing"
}

@test "SPECTRA_NO_VERIFY=1 skips the check" {
  bootstrap_installed_state
  local repo_dir
  repo_dir="$(create_fake_repo)"

  # Remove orchestration.md to create a detectable issue
  rm "$repo_dir/shared/orchestration.md"

  run env SPECTRA_NO_VERIFY=1 "$SPECTRA_CLI" link "$repo_dir"
  assert_success
  refute_output --partial "Smoke test"
}
