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
  CODEX_PROFILE="$TEST_TEMP/codex-home"
  AMBIENT_HOME="$TEST_TEMP/ambient-home"
  mkdir -p "$WORKSPACE/src" "$SESSION" "$FAKE_DIR" "$CODEX_PROFILE" \
    "$AMBIENT_HOME/.agents/skills/unrelated"
  chmod 700 "$CODEX_PROFILE"
  printf '%s\n' '{"test_auth":"not-a-real-secret"}' > "$CODEX_PROFILE/auth.json"
  printf '%s\n' 'model_reasoning_effort = "low"' > "$CODEX_PROFILE/config.toml"
  chmod 600 "$CODEX_PROFILE/auth.json" "$CODEX_PROFILE/config.toml"
  printf '%s\n' 'unrelated skill' > "$AMBIENT_HOME/.agents/skills/unrelated/SKILL.md"
  printf '%s\n' 'def example():' '    return 1' > "$WORKSPACE/src/example.py"
  export HOME="$AMBIENT_HOME"
  export CODEX_HOME="$AMBIENT_HOME/.codex"
  export SPECTRA_CODEX_MODEL_STANDARD="fake-standard-model"
}

teardown() { _common_teardown; }

write_good_fake() {
  cat > "$FAKE_CODEX" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
log="$(dirname "$0")/invocations.log"
log_environment() {
  printf 'environment\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$HOME" "$CODEX_HOME" "$CODEX_SQLITE_HOME" "$TMPDIR" \
    "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME:$XDG_STATE_HOME" >> "$log"
  [[ ! -e "$HOME/.agents/skills/unrelated/SKILL.md" ]]
  [[ -f "$CODEX_HOME/auth.json" ]]
  for private_dir in "$HOME" "$CODEX_SQLITE_HOME" "$TMPDIR" "$XDG_CONFIG_HOME" \
    "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    [[ -d "$private_dir" ]]
    [[ -z "$(find "$private_dir" -mindepth 1 -print -quit)" ]]
  done
}
if [[ "${1:-}" == "--version" ]]; then
  log_environment version
  printf 'version\n' >> "$log"
  printf 'codex-cli 99.0.0-test\n'
  exit 0
fi
[[ "${1:-}" == "exec" ]]
shift
stage="" output="" model="" credential_store=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) credential_store="$2"; shift 2 ;;
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
[[ "$credential_store" == 'cli_auth_credentials_store="file"' ]]
log_environment exec
printf 'start %s\n' "$worker" >> "$log"
if [[ -f "$(dirname "$0")/mutate-profile" && ! -f "$(dirname "$0")/profile-mutated" ]]; then
  printf '%s\n' '{"mutated":"not-a-real-secret"}' > "$(dirname "$0")/auth.json"
  chmod 600 "$(dirname "$0")/auth.json"
  mv "$(dirname "$0")/auth.json" "$CODEX_HOME/auth.json"
  : > "$(dirname "$0")/profile-mutated"
fi
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
    -c) shift 2 ;;
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
    -c) shift 2 ;;
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
    --codex-home "$CODEX_PROFILE" \
    --max-concurrency "$concurrency" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["approval_token"])'
}

@test "preview binds inputs and configuration without invoking codex exec" {
  write_good_fake

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE" \
    --max-concurrency 2
  assert_success
  assert_output --partial '"status": "approval-required"'
  assert_output --partial '"codex_invoked": false'
  assert_output --partial '"project_content_transmitted": false'
  assert_output --partial '"sha256:'
  assert_output --partial '"src/example.py"'
  refute_output --partial 'not-a-real-secret'

  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "execute rejects a stale approval before codex exec" {
  write_good_fake

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE" \
    --max-concurrency 2 \
    --approve 'sha256:not-the-preview'
  [ "$status" -eq 2 ]
  assert_output --partial 'approval token does not match'

  run grep '^start ' "$FAKE_DIR/invocations.log"
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
    --codex-home "$CODEX_PROFILE" \
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
    --codex-home "$CODEX_PROFILE" \
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
  run python3 - "$FAKE_DIR/invocations.log" "$SESSION/budget-metrics.json" \
    "$CODEX_PROFILE" "$AMBIENT_HOME" "$SESSION" <<'PY'
import json, sys
active = maximum = execs = 0
environments = []
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("start "):
        active += 1
        execs += 1
        maximum = max(maximum, active)
    elif line.startswith("end "):
        active -= 1
    elif line.startswith("environment\t"):
        environments.append(line.rstrip("\n").split("\t"))
metrics = json.load(open(sys.argv[2], encoding="utf-8"))
assert execs == 3
assert active == 0
assert maximum == 2
assert metrics["agent_spawns"] == 3
assert metrics["model_calls"] == 3
assert environments
for fields in environments:
    _, phase, home, codex_home, sqlite_home, tmpdir, xdg_config, xdg_cache, xdg_data_state = fields
    assert codex_home == __import__("os").path.realpath(sys.argv[3])
    assert home != sys.argv[4]
    assert sqlite_home != codex_home
    assert home != codex_home
    assert len({home, sqlite_home, tmpdir, xdg_config, xdg_cache}) == 5
    xdg_data, xdg_state = xdg_data_state.split(":", 1)
    assert xdg_data != xdg_state
    if phase == "exec":
        prefix = __import__("os").path.realpath(sys.argv[5]) + "/.codex-executor/"
        assert home.startswith(prefix)
        import stat
        for location in (home, sqlite_home, tmpdir, xdg_config, xdg_cache, xdg_data, xdg_state):
            assert stat.S_IMODE(__import__("os").stat(location).st_mode) == 0o700
print("OK")
PY
  assert_success
  assert_output 'OK'

  run grep -R 'not-a-real-secret' "$FAKE_DIR/invocations.log" \
    "$SESSION/.codex-executor"
  assert_failure
}

@test "an invalid reviewer artifact cannot reach the final artifact directory" {
  write_bad_fake
  local token
  token="$(preview_token 1)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE" \
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
    --codex-home "$CODEX_PROFILE" \
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
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE"
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
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE"
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
    --codex-home "$CODEX_PROFILE" \
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
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'no enforceable turn limit'

  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "preview exposes provider-run proxy cost accounting" {
  write_good_fake

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" \
    --codex-home "$CODEX_PROFILE"
  assert_success
  assert_output --partial '"unit": "provider_process_runs"'
  assert_output --partial '"budget_model_calls_is_proxy": true'
  assert_output --partial '"internal_model_turns_available": false'
}

@test "preview requires an explicit Codex home" {
  write_good_fake

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" \
    --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX"
  [ "$status" -eq 2 ]
  assert_output --partial '--codex-home'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]
}

@test "preview requires owner-readable nonempty file authentication" {
  write_good_fake
  rm "$CODEX_PROFILE/auth.json"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must contain owner-only auth.json'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]

  : > "$CODEX_PROFILE/auth.json"
  chmod 600 "$CODEX_PROFILE/auth.json"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must not be empty'

  printf '%s\n' '{"test_auth":"not-a-real-secret"}' > "$CODEX_PROFILE/auth.json"
  chmod 200 "$CODEX_PROFILE/auth.json"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must be readable by its owner'
}

@test "preview rejects symlinked or permissive execution profiles before probing Codex" {
  write_good_fake
  chmod 755 "$CODEX_PROFILE"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must not grant group or other permissions'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]

  chmod 700 "$CODEX_PROFILE"
  chmod 644 "$CODEX_PROFILE/auth.json"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'authentication material must not grant group or other permissions'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]

  chmod 600 "$CODEX_PROFILE/auth.json"
  chmod 644 "$CODEX_PROFILE/config.toml"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'profile configuration config.toml must not grant group or other permissions'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]

  chmod 600 "$CODEX_PROFILE/config.toml"
  local linked="$TEST_TEMP/linked-codex-home"
  ln -s "$CODEX_PROFILE" "$linked"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$linked"
  [ "$status" -eq 2 ]
  assert_output --partial 'existing non-symlink directory'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]
}

@test "preview rejects installed skills and nonminimal profile state" {
  write_good_fake
  mkdir "$CODEX_PROFILE/skills"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must not contain skills'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]

  rmdir "$CODEX_PROFILE/skills"
  printf '%s\n' '{}' > "$CODEX_PROFILE/history.json"
  chmod 600 "$CODEX_PROFILE/history.json"
  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'contains unexpected entry: history.json'
  [[ ! -e "$FAKE_DIR/invocations.log" ]]
}

@test "preview refuses to stage repository agent skills" {
  write_good_fake
  mkdir -p "$WORKSPACE/src/.agents/skills/repository-skill"
  printf '%s\n' 'repository skill' > "$WORKSPACE/src/.agents/skills/repository-skill/SKILL.md"

  run python3 "$EXECUTOR" preview "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE"
  [ "$status" -eq 2 ]
  assert_output --partial 'must not stage agent configuration'
  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "changing profile configuration invalidates approval before Codex exec" {
  write_good_fake
  local token
  token="$(preview_token 1)"
  printf '%s\n' 'approval_policy = "never"' >> "$CODEX_PROFILE/config.toml"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE" \
    --max-concurrency 1 --approve "$token"
  [ "$status" -eq 2 ]
  assert_output --partial 'approval token does not match'
  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
  [[ ! -e "$SESSION/budget-metrics.json" ]]
}

@test "replacing authentication material invalidates approval without reading it" {
  write_good_fake
  local token replacement
  token="$(preview_token 1)"
  replacement="$TEST_TEMP/auth.json"
  printf '%s\n' '{"replacement":"still-not-a-real-secret"}' > "$replacement"
  chmod 600 "$replacement"
  mv "$replacement" "$CODEX_PROFILE/auth.json"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE" \
    --max-concurrency 1 --approve "$token"
  [ "$status" -eq 2 ]
  assert_output --partial 'approval token does not match'
  refute_output --partial 'replacement'
  run grep '^start ' "$FAKE_DIR/invocations.log"
  assert_failure
}

@test "profile mutation after preflight prevents every later Codex spawn" {
  write_good_fake
  : > "$FAKE_DIR/mutate-profile"
  local token
  token="$(preview_token 1)"

  run python3 "$EXECUTOR" execute "$PLAN" \
    --workspace-root "$WORKSPACE" --session-root "$SESSION" \
    --codex-bin "$FAKE_CODEX" --codex-home "$CODEX_PROFILE" \
    --max-concurrency 1 --approve "$token"
  [ "$status" -eq 3 ]
  assert_output --partial 'Codex execution profile changed after approval'
  run grep -c '^start ' "$FAKE_DIR/invocations.log"
  assert_success
  assert_output '1'
}
