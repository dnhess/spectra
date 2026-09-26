#!/usr/bin/env bats

load 'test_helper/common-setup'
load '../node_modules/bats-support/load'
load '../node_modules/bats-assert/load'

setup() {
  _common_setup
  WORKFLOW="$PROJECT_ROOT/.github/workflows/codex-clean-host-inspect.yml"
  DOCKERFILE="$PROJECT_ROOT/.github/codex-clean-host/Dockerfile"
  RUNNER="$PROJECT_ROOT/.github/codex-clean-host/run-inspection.py"
  FAKE_BIN="$TEST_TEMP/bin"
  FAKE_DOCKER_LOG="$TEST_TEMP/docker.jsonl"
  FAKE_REPORT="$TEST_TEMP/report.json"
  CODEX_HASH="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  IMAGE="spectra-codex-clean-host:123-1"
  COMMIT="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  export FAKE_DOCKER_LOG FAKE_REPORT CODEX_HASH
  export FAKE_DOCKER_MODE=success
  mkdir -p "$FAKE_BIN"

  python3 - "$FAKE_REPORT" "$CODEX_HASH" <<'PY'
import hashlib
import hashlib
import json
import sys

empty_hash = hashlib.sha256(b"[]").hexdigest()
report = {
    "version": "1.0.0",
    "operation": "inspect-context",
    "status": "inspected",
    "codex": {
        "version_descriptor": {
            "stdout": {"bytes": 18, "sha256": "1" * 64},
            "stderr": {"bytes": 0, "sha256": "2" * 64},
        },
        "size": 123456,
        "sha256": sys.argv[2],
    },
    "context": {
        "diagnostic_version": "redacted-prompt-context-v1",
        "message_count": 0,
        "messages": [],
        "content_boundary_sha256": empty_hash,
        "metadata_boundary_sha256": empty_hash,
        "system_skills": {
            "system_tree_present": False,
            "observed_safe_names": [],
            "unknown_name_count": 0,
            "unknown_names_sha256": None,
        },
        "raw_content_emitted": False,
    },
    "codex_cli_debug_subcommand_invoked": True,
    "authentication_supplied": False,
    "provider_subcommand_invoked": False,
    "project_content_supplied": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(report, output, sort_keys=True)
PY

  cat > "$FAKE_BIN/docker" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
import time

args = sys.argv[1:]
with open(os.environ["FAKE_DOCKER_LOG"], "a", encoding="utf-8") as output:
    output.write(json.dumps(args, separators=(",", ":")) + "\n")

mode = os.environ.get("FAKE_DOCKER_MODE", "success")
if args[:2] == ["image", "inspect"]:
    architecture = "arm64" if mode == "arch" else "amd64"
    volumes = {"/escape": {}} if mode == "volumes" else None
    print(json.dumps({"Os": "linux", "Architecture": architecture, "Config": {"Volumes": volumes}}))
    raise SystemExit(0)
if args[:1] == ["rm"]:
    raise SystemExit(0)
if args[:1] != ["run"]:
    raise SystemExit(93)
if mode == "timeout":
    time.sleep(10)
if mode == "stdout-overflow":
    os.write(1, b"x" * (1024 * 1024 + 1))
    raise SystemExit(0)
if mode == "stderr-overflow":
    os.write(2, b"x" * (256 * 1024 + 1))
    raise SystemExit(0)
with open(os.environ["FAKE_REPORT"], encoding="utf-8") as source:
    report = json.load(source)
if mode == "schema":
    report["context"]["system_skills"]["raw_name"] = "must-not-escape"
if mode == "hash":
    report["codex"]["sha256"] = "f" * 64
if mode == "boundary":
    report["context"]["content_boundary_sha256"] = "e" * 64
if mode == "content-value-boundary":
    fingerprint = {"json_type": "string", "bytes": 4, "sha256": "3" * 64}
    report["context"]["message_count"] = 1
    report["context"]["messages"] = [{
        "index": 0,
        "shape": "object",
        "known_keys": ["content", "role", "type"],
        "unknown_key_count": 0,
        "unknown_values": None,
        "role": "developer",
        "type": "message",
        "envelope_metadata": None,
        "content": [],
        "content_value": fingerprint,
    }]
    old_boundary = [{
        "index": 0,
        "role": "developer",
        "type": "message",
        "content": [],
    }]
    metadata_boundary = [{
        "index": 0,
        "known_keys": ["content", "role", "type"],
        "unknown_values": None,
        "envelope_metadata": None,
    }]
    canonical = lambda value: json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    report["context"]["content_boundary_sha256"] = hashlib.sha256(
        canonical(old_boundary)
    ).hexdigest()
    report["context"]["metadata_boundary_sha256"] = hashlib.sha256(
        canonical(metadata_boundary)
    ).hexdigest()
serialized = json.dumps(report, sort_keys=True)
if mode == "duplicate-root":
    serialized = serialized[:-1] + ', "version": "1.0.0"}'
if mode == "duplicate-nested":
    marker = '"raw_content_emitted": false'
    serialized = serialized.replace(marker, marker + ', "raw_content_emitted": false', 1)
print(serialized)
PY
  chmod +x "$FAKE_BIN/docker"
}

teardown() { _common_teardown; }

invoke_runner() {
  local evidence_root="$1"
  shift
  run env PATH="$FAKE_BIN:$PATH" python3 "$RUNNER" \
    --image "$IMAGE" \
    --expected-sha256 "$CODEX_HASH" \
    --evidence-root "$evidence_root" \
    --codex-version 0.147.0 \
    --workflow-commit "$COMMIT" \
    --runner-os Linux \
    --runner-arch X64 \
    "$@"
}

@test "clean-host workflow is manual-only secret-free and immutably pinned" {
  run grep -F 'workflow_dispatch:' "$WORKFLOW"
  assert_success
  run grep -E '^[[:space:]]+(push|pull_request|schedule):' "$WORKFLOW"
  assert_failure
  run grep -F 'persist-credentials: false' "$WORKFLOW"
  assert_success
  run grep -F '${{ secrets.' "$WORKFLOW"
  assert_failure
  run grep -E 'uses: actions/(checkout|upload-artifact)@[0-9a-f]{40}([[:space:]]|$)' "$WORKFLOW"
  assert_success
  [[ "${#lines[@]}" -eq 2 ]]
  run grep -E '^FROM --platform=linux/amd64 [^[:space:]@]+@sha256:[0-9a-f]{64}([[:space:]]|$)' "$DOCKERFILE"
  assert_success
  [[ "${#lines[@]}" -eq 2 ]]
}

@test "runner paths use only context-valid step environments" {
  job_env="$(sed -n '/^    env:$/,/^    steps:$/p' "$WORKFLOW")"
  [[ "$job_env" != *'${{ runner.'* ]]

  run grep -F '          BUILD_ROOT: ${{ runner.temp }}/spectra-codex-clean-host-build-${{ github.run_id }}-${{ github.run_attempt }}' "$WORKFLOW"
  assert_success
  [[ "${#lines[@]}" -eq 2 ]]

  run grep -F '          EVIDENCE_ROOT: ${{ runner.temp }}/spectra-codex-clean-host-evidence-${{ github.run_id }}-${{ github.run_attempt }}' "$WORKFLOW"
  assert_success
  [[ "${#lines[@]}" -eq 2 ]]
}

@test "workflow delegates evidence capture to the host-bounded runner" {
  run grep -F 'docker build --platform linux/amd64 --pull --no-cache' "$WORKFLOW"
  assert_success
  run grep -F 'python3 .github/codex-clean-host/run-inspection.py' "$WORKFLOW"
  assert_success
  run grep -F 'docker run' "$WORKFLOW"
  assert_failure
  run grep -F 'inspect-context.stderr' "$WORKFLOW"
  assert_failure
  run grep -F 'retention-days: 3' "$WORKFLOW"
  assert_success
  upload_block="$(sed -n '/uses: actions\/upload-artifact@/,$p' "$WORKFLOW")"
  [[ "$upload_block" == *'inspect-context.json'* ]]
  [[ "$upload_block" == *'provenance.json'* ]]
  [[ "$upload_block" != *'stderr'* ]]
}

@test "image selects and verifies the exact Linux x64 ELF executable" {
  run grep -F 'node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex' "$DOCKERFILE"
  assert_success
  run grep -F 'sha256sum --check --strict' "$DOCKERFILE"
  assert_success
  run grep -F "data[:4] == b'\\\\x7fELF'" "$DOCKERFILE"
  assert_success
  run grep -F "struct.unpack('<H', data[18:20])[0] == 62" "$DOCKERFILE"
  assert_success
  run grep -Ei 'auth|token|credential' "$DOCKERFILE"
  assert_failure
}

@test "successful fake inspection writes only reconstructed evidence" {
  local evidence="$TEST_TEMP/evidence-success"
  invoke_runner "$evidence"
  assert_success
  run find "$evidence" -mindepth 1 -maxdepth 1 -type f -print
  assert_success
  [[ "${#lines[@]}" -eq 2 ]]
  [[ -f "$evidence/inspect-context.json" ]]
  [[ -f "$evidence/provenance.json" ]]
  run python3 - "$evidence" "$CODEX_HASH" "$COMMIT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
report_bytes = (root / "inspect-context.json").read_bytes()
report = json.loads(report_bytes)
provenance = json.loads((root / "provenance.json").read_text())
assert report["context"]["raw_content_emitted"] is False
assert report["codex"]["sha256"] == sys.argv[2]
assert provenance["workflow_commit"] == sys.argv[3]
assert provenance["authorization_effect"] == "evidence-only"
assert provenance["report_sha256"] == hashlib.sha256(report_bytes).hexdigest()
assert not any("raw" in path.name or "stderr" in path.name for path in root.iterdir())
assert all((path.stat().st_mode & 0o777) == 0o600 for path in root.iterdir())
PY
  assert_success
}

@test "fake inspection uses the exact hardened Docker argv and named cleanup" {
  invoke_runner "$TEST_TEMP/evidence-argv"
  assert_success
  run python3 - "$FAKE_DOCKER_LOG" "$IMAGE" <<'PY'
import json
import sys

calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
runs = [call for call in calls if call and call[0] == "run"]
assert runs == [[
    "run", "--platform", "linux/amd64", "--name", "spectra-codex-clean-host-inspect",
    "--network", "none", "--read-only", "--cap-drop", "ALL", "--security-opt",
    "no-new-privileges=true", "--pids-limit", "64", "--memory", "1g", "--user",
    "65532:65532", "--log-driver", "none", "--tmpfs",
    "/tmp:rw,nosuid,nodev,noexec,size=64m,mode=1777", "--tmpfs",
    "/home/spectra:rw,nosuid,nodev,noexec,size=16m,mode=0700,uid=65532,gid=65532",
    "--entrypoint", "/usr/bin/env", sys.argv[2], "-i",
    "PATH=/usr/local/bin:/usr/bin:/bin", "HOME=/home/spectra", "LANG=C.UTF-8",
    "PYTHONDONTWRITEBYTECODE=1",
    "/usr/local/bin/python3", "/opt/spectra/codex-executor.py", "inspect-context",
    "--codex-bin", "/usr/local/bin/codex",
]]
removes = [call for call in calls if call[:3] == ["rm", "-f", "spectra-codex-clean-host-inspect"]]
assert len(removes) >= 2
PY
  assert_success
}

@test "diagnostic producer binds non-list content fingerprints into its boundary" {
  run env PYTHONDONTWRITEBYTECODE=1 python3 - \
    "$PROJECT_ROOT/adapters/codex/codex-executor.py" "$TEST_TEMP" <<'PY'
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("codex_executor", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)

report = module.redact_prompt_context(
    [{"role": "developer", "type": "message", "content": "test"}],
    Path(sys.argv[2]),
    Path(sys.argv[2]) / "missing-codex-home",
)
message = report["messages"][0]
boundary = [{
    "index": 0,
    "role": "developer",
    "type": "message",
    "content": [],
    "content_value": message["content_value"],
}]
old_boundary = [{
    "index": 0,
    "role": "developer",
    "type": "message",
    "content": [],
}]
canonical = lambda value: json.dumps(
    value,
    sort_keys=True,
    separators=(",", ":"),
    ensure_ascii=False,
    allow_nan=False,
).encode("utf-8")
assert report["content_boundary_sha256"] == hashlib.sha256(canonical(boundary)).hexdigest()
assert report["content_boundary_sha256"] != hashlib.sha256(canonical(old_boundary)).hexdigest()
PY
  assert_success
}

@test "schema hash boundary and duplicate-key failures emit no artifact and clean up" {
  for mode in schema hash boundary content-value-boundary duplicate-root duplicate-nested; do
    export FAKE_DOCKER_MODE="$mode"
    local evidence="$TEST_TEMP/evidence-$mode"
    invoke_runner "$evidence"
    assert_failure 2
    [[ -d "$evidence" ]]
    [[ -z "$(find "$evidence" -mindepth 1 -print -quit)" ]]
  done
  run grep -F 'must-not-escape' "$TEST_TEMP/evidence-schema/inspect-context.json"
  assert_failure
  run python3 - "$FAKE_DOCKER_LOG" <<'PY'
import json
import sys
calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
assert len([call for call in calls if call[:3] == ["rm", "-f", "spectra-codex-clean-host-inspect"]]) >= 6
PY
  assert_success
}

@test "stdout and stderr overflow are bounded and always cleaned up" {
  for mode in stdout-overflow stderr-overflow; do
    export FAKE_DOCKER_MODE="$mode"
    invoke_runner "$TEST_TEMP/evidence-$mode"
    assert_failure 2
    [[ -z "$(find "$TEST_TEMP/evidence-$mode" -mindepth 1 -print -quit)" ]]
  done
  run grep -F '["rm","-f","spectra-codex-clean-host-inspect"]' "$FAKE_DOCKER_LOG"
  assert_success
}

@test "timeout kills the fake runtime and performs named cleanup" {
  export FAKE_DOCKER_MODE=timeout
  local evidence="$TEST_TEMP/evidence-timeout"
  run env PATH="$FAKE_BIN:$PATH" PYTHONDONTWRITEBYTECODE=1 python3 - "$RUNNER" \
    --image "$IMAGE" \
    --expected-sha256 "$CODEX_HASH" \
    --evidence-root "$evidence" \
    --codex-version 0.147.0 \
    --workflow-commit "$COMMIT" \
    --runner-os Linux \
    --runner-arch X64 <<'PY'
import importlib.util
import sys

runner = sys.argv[1]
arguments = sys.argv[2:]
spec = importlib.util.spec_from_file_location("clean_host_runner", runner)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
module.TIMEOUT_SECONDS = 0.15
sys.argv = [runner, *arguments]
raise SystemExit(module.main())
PY
  assert_failure 2
  [[ -z "$(find "$evidence" -mindepth 1 -print -quit)" ]]
  run grep -F '["rm","-f","spectra-codex-clean-host-inspect"]' "$FAKE_DOCKER_LOG"
  assert_success
}

@test "wrong image architecture or declared volumes fail before runtime" {
  for mode in arch volumes; do
    export FAKE_DOCKER_MODE="$mode"
    invoke_runner "$TEST_TEMP/evidence-$mode"
    assert_failure 2
  done
  run python3 - "$FAKE_DOCKER_LOG" <<'PY'
import json
import sys
calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
assert not any(call and call[0] == "run" for call in calls)
PY
  assert_success
}

@test "runner rejects arguments that could weaken the Docker boundary" {
  for forbidden in \
    '--timeout=1' \
    '--container-name=override' \
    '--volume=/host:/container' \
    '--docker-arg=--privileged'; do
    invoke_runner "$TEST_TEMP/evidence-args-${forbidden%%=*}" "$forbidden"
    assert_failure 2
  done
  [[ ! -e "$FAKE_DOCKER_LOG" ]]
}
