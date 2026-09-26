#!/usr/bin/env bats
# Tests for provider runtime dispatch without requiring a real Codex install.

load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

install_test_adapter() {
  local adapter="$SPECTRA_HOME/skills/adapters/codex/codex-runtime.sh"
  mkdir -p "$(dirname "$adapter")"
  cat > "$adapter" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'adapter:'
printf ' %s' "$@"
printf '\n'
SCRIPT
  chmod +x "$adapter"
}

@test "runtime list works before installation" {
  run "$SPECTRA_CLI" runtime list
  assert_success
  assert_output --partial "codex"
}

@test "runtime commands require an installed Spectra state" {
  run "$SPECTRA_CLI" runtime codex doctor
  assert_failure
  assert_output --partial "not installed"
}

@test "runtime rejects unknown providers clearly" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" runtime unknown doctor
  assert_failure
  assert_output --partial "Unknown runtime: unknown"
}

@test "runtime reports a missing Codex adapter clearly" {
  bootstrap_installed_state
  run "$SPECTRA_CLI" runtime codex doctor
  assert_failure
  assert_output --partial "Runtime adapter not found"
}

@test "runtime passes capabilities to the release adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex capabilities
  assert_success
  assert_output "adapter: capabilities"
}

@test "runtime passes validate and render plans to the adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex validate plans/review.json
  assert_success
  assert_output "adapter: validate plans/review.json"

  run "$SPECTRA_CLI" runtime codex render plans/review.json
  assert_success
  assert_output "adapter: render plans/review.json"
}

@test "runtime passes dry-run output paths to the adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex dry-run plans/review.json --out "$TEST_TEMP/out.json"
  assert_success
  assert_output "adapter: dry-run plans/review.json --out $TEST_TEMP/out.json"
}

@test "runtime passes preview and execute gates to the adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex preview plans/review.json \
    --workspace-root "$TEST_TEMP/workspace" --session-root "$TEST_TEMP/session" \
    --codex-bin "$TEST_TEMP/codex" --codex-home "$TEST_TEMP/codex-home"
  assert_success
  assert_output --partial "preview plans/review.json"
  assert_output --partial "--codex-bin $TEST_TEMP/codex"
  assert_output --partial "--codex-home $TEST_TEMP/codex-home"

  run "$SPECTRA_CLI" runtime codex preview plans/review.json \
    --workspace-root="$TEST_TEMP/workspace" --session-root="$TEST_TEMP/session" \
    --codex-bin="$TEST_TEMP/codex" --codex-home="$TEST_TEMP/codex-home"
  assert_success
  assert_output --partial "--codex-home=$TEST_TEMP/codex-home"

  run "$SPECTRA_CLI" runtime codex execute plans/review.json \
    --workspace-root "$TEST_TEMP/workspace" --session-root "$TEST_TEMP/session" \
    --codex-bin "$TEST_TEMP/codex" --codex-home "$TEST_TEMP/codex-home" --approve sha256:approved
  assert_success
  assert_output --partial "execute plans/review.json"
  assert_output --partial "--approve sha256:approved"
  assert_output --partial "--codex-home $TEST_TEMP/codex-home"
}

@test "runtime passes redacted context inspection to the adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex inspect-context --codex-bin "$TEST_TEMP/codex"
  assert_success
  assert_output "adapter: inspect-context --codex-bin $TEST_TEMP/codex"

  run "$SPECTRA_CLI" runtime codex inspect-context --codex-bin="$TEST_TEMP/codex"
  assert_success
  assert_output "adapter: inspect-context --codex-bin=$TEST_TEMP/codex"
}

@test "runtime resolves adapters from the dev repository" {
  bootstrap_installed_state
  local repo_dir="$TEST_TEMP/dev-repo"
  mkdir -p "$repo_dir/adapters/codex"
  cat > "$repo_dir/adapters/codex/codex-runtime.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'dev adapter: %s\n' "$1"
SCRIPT
  chmod +x "$repo_dir/adapters/codex/codex-runtime.sh"
  echo "dev" > "$SPECTRA_HOME/mode"
  echo "$repo_dir" > "$SPECTRA_HOME/dev-repo"

  run "$SPECTRA_CLI" runtime codex doctor
  assert_success
  assert_output "dev adapter: doctor"
}

@test "runtime validates command syntax before invoking the adapter" {
  bootstrap_installed_state
  install_test_adapter

  run "$SPECTRA_CLI" runtime codex dry-run
  assert_failure
  assert_output --partial "Usage"

  run "$SPECTRA_CLI" runtime codex inspect-context
  assert_failure
  assert_output --partial "--codex-bin"

  run "$SPECTRA_CLI" runtime codex doctor extra
  assert_failure
  assert_output --partial "Usage"

  run "$SPECTRA_CLI" runtime codex preview plans/review.json \
    --workspace-root "$TEST_TEMP/workspace" --session-root "$TEST_TEMP/session" \
    --codex-bin "$TEST_TEMP/codex"
  assert_failure
  assert_output --partial "--codex-home"

  run "$SPECTRA_CLI" runtime codex execute plans/review.json \
    --workspace-root "$TEST_TEMP/workspace" --session-root "$TEST_TEMP/session" \
    --codex-bin "$TEST_TEMP/codex" --approve sha256:approved
  assert_failure
  assert_output --partial "--codex-home"
}
