#!/usr/bin/env bats
# Tests for spectra update command

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

SPECTRA_TEST_SHIM=""

# Helper to get the shim path (available after _common_setup sets PROJECT_ROOT)
get_shim() {
  echo "$PROJECT_ROOT/test/test_helper/spectra-test-shim.bash"
}

# --- update tests ---

@test "update rejects dev mode" {
  bootstrap_installed_state
  echo "dev" > "$SPECTRA_HOME/mode"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_failure
  assert_output --partial "dev mode"
}

@test "update detects already up-to-date" {
  bootstrap_installed_state
  echo "0.3.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success
  assert_output --partial "Already up to date"
}

@test "update downloads and swaps skills" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  # skills-prev should exist after the swap
  [[ -d "$SPECTRA_HOME/skills-prev" ]]
}

@test "update preserves skills-prev for rollback" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  # Plant an identifiable marker in the current skills dir
  echo "old-skills-marker" > "$SPECTRA_HOME/skills/shared/marker.txt"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  # The old skills (with our marker) should now be in skills-prev
  [[ -f "$SPECTRA_HOME/skills-prev/shared/marker.txt" ]]
  local marker
  marker="$(cat "$SPECTRA_HOME/skills-prev/shared/marker.txt")"
  [[ "$marker" == "old-skills-marker" ]]
}

@test "update copies bin files from tarball" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  # bin/spectra should exist and be executable
  [[ -f "$SPECTRA_HOME/bin/spectra" ]]
  [[ -x "$SPECTRA_HOME/bin/spectra" ]]
}

@test "update writes new version to VERSION_FILE" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  local version
  version="$(cat "$SPECTRA_HOME/version")"
  [[ "$version" == "0.3.0" ]]
}

@test "update saves prev-version for rollback" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  [[ -f "$SPECTRA_HOME/prev-version" ]]
  local prev
  prev="$(cat "$SPECTRA_HOME/prev-version")"
  [[ "$prev" == "0.2.0" ]]
}

@test "update re-merges permissions" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  # settings.json should still have Spectra permissions
  [[ -f "$CLAUDE_HOME/settings.json" ]]
  run grep "json-write.sh" "$CLAUDE_HOME/settings.json"
  assert_success
}

@test "update cleans up tmp_dir on success" {
  bootstrap_installed_state
  echo "0.2.0" > "$SPECTRA_HOME/version"

  create_fake_tarball "$TEST_TEMP/release" "v0.3.0"

  local shim
  shim="$(get_shim)"
  run "$shim" update
  assert_success

  # No skills-staging directory should remain
  [[ ! -d "$SPECTRA_HOME/skills-staging" ]]
}
