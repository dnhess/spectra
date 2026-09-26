#!/usr/bin/env bats

load test_helper/common-setup

setup() {
  _common_setup
  RUNTIME="$PROJECT_ROOT/adapters/codex/codex-runtime.sh"
  FIXTURE="$PROJECT_ROOT/shared/runtime/fixtures/peer-review-quick.plan.json"
}
teardown() { _common_teardown; }

@test "dry-run is local-only and never invokes a codex executable" {
  local fake_bin="$TEST_TEMP/bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'echo unexpected-codex-invocation >&2' 'exit 99' > "$fake_bin/codex"
  chmod +x "$fake_bin/codex"

  run env PATH="$fake_bin:$PATH" "$RUNTIME" dry-run "$FIXTURE"
  assert_success
  assert_output --partial '"project_content_transmitted": false'
  assert_output --partial '"codex_invoked": false'
  refute_output --partial "unexpected-codex-invocation"
}

@test "dry-run writes only an explicit non-symlink absolute output path" {
  local output_dir
  output_dir="$(mktemp -d "$PROJECT_ROOT/.codex-runtime-test.XXXXXX")"
  local output="$output_dir/result.json"
  "$RUNTIME" dry-run "$FIXTURE" --out "$output" > "$output_dir/stdout.json"
  [[ -f "$output" ]]
  run grep '"project_content_transmitted": false' "$output"
  assert_success
  rm -rf "$output_dir"
}

@test "dry-run refuses a symlink output target" {
  local output_dir
  output_dir="$(mktemp -d "$PROJECT_ROOT/.codex-runtime-test.XXXXXX")"
  local target="$output_dir/target.json"
  local output="$output_dir/result-link.json"
  printf '{}\n' > "$target"
  ln -s "$target" "$output"
  run "$RUNTIME" dry-run "$FIXTURE" --out "$output"
  assert_failure
  assert_output --partial "regular file"
  rm -rf "$output_dir"
}

@test "doctor proves an explicitly configured Codex executable is usable without a model call" {
  local fake_bin="$TEST_TEMP/codex"
  cat > "$fake_bin" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]]
printf 'codex-cli test\n'
SCRIPT
  chmod +x "$fake_bin"

  run env SPECTRA_CODEX_BIN="$fake_bin" "$RUNTIME" doctor
  assert_success
  assert_output --partial '"status": "ready"'
  assert_output --partial '"execution_ready": true'
  assert_output --partial '"codex_invoked": false'
  assert_output --partial 'worker tools request no network'
}

@test "inspect-context is offline redacted and requires no execution profile" {
  local fake_bin="$TEST_TEMP/codex"
  cat > "$fake_bin" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'codex-cli test\n'
  exit 0
fi
[[ "${1:-}" == "-C" ]]
shift 2
while [[ "${1:-}" == "--disable" ]]; do shift 2; done
[[ "${1:-}" == "debug" && "${2:-}" == "prompt-input" ]]
printf '%s\n' '[{"type":"message","role":"developer","id":"dynamic-id","internal_chat_message_metadata_passthrough":{},"content":[{"type":"input_text","text":"unapproved diagnostic fixture"}]},{"type":"message","role":"user","content":[{"type":"input_text","text":"spectra-prompt-context-probe-v1"}]}]'
SCRIPT
  chmod +x "$fake_bin"

  run "$RUNTIME" inspect-context --codex-bin "$fake_bin"
  assert_success
  assert_output --partial '"operation": "inspect-context"'
  assert_output --partial '"authentication_supplied": false'
  assert_output --partial '"provider_subcommand_invoked": false'
  assert_output --partial '"project_content_supplied": false'
  assert_output --partial '"codex_cli_debug_subcommand_invoked": true'
  assert_output --partial '"raw_content_emitted": false'
  refute_output --partial 'unapproved diagnostic fixture'
}
