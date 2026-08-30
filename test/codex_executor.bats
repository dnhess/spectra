#!/usr/bin/env bats

load test_helper/common-setup

setup() {
  _common_setup
  EXECUTOR="$PROJECT_ROOT/adapters/codex/codex-executor.py"
  PLAN="$PROJECT_ROOT/shared/runtime/fixtures/peer-review-quick.plan.json"
  WORKSPACE="$TEST_TEMP/workspace"
  SESSION="$TEST_TEMP/sessions/peer-review/peer-review-quick-fixture"
  FAKE_DIR="$TEST_TEMP/fake-codex"
  FAKE_CODEX="$FAKE_DIR/codex"
  mkdir -p "$WORKSPACE/src" "$SESSION" "$FAKE_DIR"
  printf '%s\n' 'def example():' '    return 1' > "$WORKSPACE/src/example.py"
  export SPECTRA_CODEX_MODEL_STANDARD="fake-standard-model"
}

teardown() { _common_teardown; }

write_good_fake() {
  cat > "$FAKE_CODEX" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
log="$(dirname "$0")/invocations.log"
if [[ "${1:-}" == "--version" ]]; then
  printf 'version\n' >> "$log"
  printf 'codex-cli 99.0.0-test\n'
  exit 0
fi
[[ "${1:-}" == "exec" ]]
shift
stage="" output="" model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) stage="$2"; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --skip-git-repo-check|--ephemeral|--ignore-user-config|--ignore-rules) shift ;;
    --disable) shift 2 ;;
    --sandbox|--output-schema|--color) shift 2 ;;
    -) shift; break ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
prompt="$(sed -n '1,200p')"
worker="$(basename "$stage")"
[[ "$prompt" == *"exactly \"$worker\""* ]]
[[ "$model" == "fake-standard-model" ]]
printf 'start %s\n' "$worker" >> "$log"
sleep 0.12
printf '{"reviewer":"%s","findings":[]}\n' "$worker" > "$output"
printf 'end %s\n' "$worker" >> "$log"
FAKE
  chmod +x "$FAKE_CODEX"
}

write_bad_fake() {
  cat > "$FAKE_CODEX" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'codex-cli 99.0.0-test\n'
  exit 0
fi
shift
stage="" output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) stage="$2"; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    --model|--sandbox|--output-schema|--color) shift 2 ;;
    --skip-git-repo-check|--ephemeral|--ignore-user-config|--ignore-rules) shift ;;
    --disable) shift 2 ;;
    -) shift; break ;;
    *) exit 64 ;;
  esac
done
sed -n '1,200p' >/dev/null
printf '{"reviewer":"wrong-reviewer","findings":[]}\n' > "$output"
FAKE
  chmod +x "$FAKE_CODEX"
}

write_partial_fake() {
  cat > "$FAKE_CODEX" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then printf 'codex-cli 99.0.0-test\n'; exit 0; fi
shift
stage="" output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) stage="$2"; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    --model|--sandbox|--output-schema|--color) shift 2 ;;
    --skip-git-repo-check|--ephemeral|--ignore-user-config|--ignore-rules) shift ;;
    --disable) shift 2 ;;
    -) shift; break ;;
    *) exit 64 ;;
  esac
done
sed -n '1,200p' >/dev/null
worker="$(basename "$stage")"
if [[ "$worker" == "security-auditor" ]]; then
  printf '{"reviewer":"wrong-reviewer","findings":[]}\n' > "$output"
else
  printf '{"reviewer":"%s","findings":[]}\n' "$worker" > "$output"
fi
FAKE
  chmod +x "$FAKE_CODEX"
}

preview_token() {
  local concurrency="${1:-2}"
  python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency "$concurrency" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["approval_token"])'
}

@test "preview binds inputs and configuration without invoking codex exec" {
  write_good_fake

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 2
  assert_success
  assert_output --partial '"status": "approval-required"'
  assert_output --partial '"codex_invoked": false'
  assert_output --partial '"project_content_transmitted": false'
  assert_output --partial '"sha256:'
  assert_output --partial '"src/example.py"'

  run grep -v '^version$' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "execute rejects a stale approval before codex exec" {
  write_good_fake

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 2 \
    --approve 'sha256:not-the-preview'
  [ "$status" -eq 2 ]
  assert_output --partial 'approval token does not match'

  run grep -v '^version$' "$FAKE_DIR/invocations.log"
  assert_failure
  [[ ! -e "$SESSION/budget-metrics.json" ]]
}

@test "editing a declared input invalidates prior approval" {
  write_good_fake
  local token
  token="$(preview_token 2)"
  printf '%s\n' 'def example():' '    return 2' > "$WORKSPACE/src/example.py"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 2 \
    --approve "$token"
  [ "$status" -eq 2 ]
  assert_output --partial 'approval token does not match'

  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "approved execution is bounded, validates, and moderator-writes artifacts" {
  write_good_fake
  local token
  token="$(preview_token 2)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 2 \
    --approve "$token"
  assert_success
  assert_output --partial '"status": "completed"'
  assert_output --partial '"completed": 3'
  assert_output --partial '"project_content_transmitted": true'

  [[ -f "$SESSION/opening/design-critic.json" ]]
  [[ -f "$SESSION/opening/reliability-engineer.json" ]]
  [[ -f "$SESSION/opening/security-auditor.json" ]]
  [[ -f "$SESSION/budget-metrics.json" ]]
  [[ -f "$SESSION/budget-policy.json" ]]
  run python3 - "$FAKE_DIR/invocations.log" "$SESSION/budget-metrics.json" <<'PY'
import json, sys
active = maximum = execs = 0
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("start "):
        active += 1
        execs += 1
        maximum = max(maximum, active)
    elif line.startswith("end "):
        active -= 1
metrics = json.load(open(sys.argv[2], encoding="utf-8"))
assert execs == 3
assert active == 0
assert maximum == 2
assert metrics["agent_spawns"] == 3
assert metrics["model_calls"] == 3
print("OK")
PY
  assert_success
  assert_output 'OK'
}

@test "an invalid reviewer artifact cannot reach the final artifact directory" {
  write_bad_fake
  local token
  token="$(preview_token 1)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 1 \
    --approve "$token"
  [ "$status" -eq 3 ]
  assert_output --partial 'quorum-failed'
  [[ ! -e "$SESSION/opening/design-critic.json" ]]
  [[ ! -e "$SESSION/opening/reliability-engineer.json" ]]
  [[ ! -e "$SESSION/opening/security-auditor.json" ]]
}

@test "continue-if-quorum accepts two valid artifacts and rejects the invalid peer" {
  write_partial_fake
  local token
  token="$(preview_token 2)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 2 \
    --approve "$token"
  assert_success
  assert_output --partial '"status": "completed"'
  assert_output --partial '"completed": 2'
  [[ -f "$SESSION/opening/design-critic.json" ]]
  [[ -f "$SESSION/opening/reliability-engineer.json" ]]
  [[ ! -e "$SESSION/opening/security-auditor.json" ]]
}

@test "preview rejects symlinks in declared workspace inputs" {
  write_good_fake
  printf 'outside\n' > "$TEST_TEMP/outside.py"
  ln -s "$TEST_TEMP/outside.py" "$WORKSPACE/src/leak.py"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX"
  [ "$status" -eq 2 ]
  assert_output --partial 'symlink forbidden'
}

@test "preview binds the session directory to the plan session id" {
  write_good_fake
  local wrong="$TEST_TEMP/sessions/peer-review/wrong-session"
  mkdir -p "$wrong"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$wrong" \
    --codex-bin "$FAKE_CODEX"
  [ "$status" -eq 2 ]
  assert_output --partial 'must equal plan.session_id'
}

@test "execute refuses a pre-existing symlinked runtime directory" {
  write_good_fake
  local outside="$TEST_TEMP/outside-runtime"
  mkdir -p "$outside"
  ln -s "$outside" "$SESSION/.codex-executor"
  local token
  token="$(preview_token 1)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --max-concurrency 1 \
    --approve "$token"
  [ "$status" -eq 2 ]
  assert_output --partial 'already contains .codex-executor'
  [[ -z "$(find "$outside" -mindepth 1 -print -quit)" ]]
}

@test "preview rejects an unenforceable multi-turn execution budget" {
  write_good_fake
  local multi_turn_plan="$TEST_TEMP/multi-turn-plan.json"
  jq '(.actions[].execution.max_turns) = 2' "$PLAN" > "$multi_turn_plan"

  run python3 "$EXECUTOR" preview "$multi_turn_plan" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX"
  [ "$status" -eq 2 ]
  assert_output --partial 'no enforceable turn limit'

  run grep -v '^version$' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "preview exposes provider-run proxy cost accounting" {
  write_good_fake

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX"
  assert_success
  assert_output --partial '"unit": "provider_process_runs"'
  assert_output --partial '"budget_model_calls_is_proxy": true'
  assert_output --partial '"internal_model_turns_available": false'
}
