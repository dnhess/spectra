#!/usr/bin/env python3
"""Run the offline clean-host inspection and emit only reconstructed evidence."""

from __future__ import annotations

import argparse
import atexit
import hashlib
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


CONTAINER_NAME = "spectra-codex-clean-host-inspect"
MAX_STDOUT = 1024 * 1024
MAX_STDERR = 256 * 1024
MAX_BINARY_SIZE = 256 * 1024 * 1024
TIMEOUT_SECONDS = 30.0
KNOWN_SKILLS = {
    "imagegen",
    "openai-docs",
    "plugin-creator",
    "skill-creator",
    "skill-installer",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
IMAGE_RE = re.compile(r"^[a-z0-9][a-z0-9./_-]{0,127}:[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-.][0-9A-Za-z.-]+)?$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


class GateError(Exception):
    """The clean-host evidence did not satisfy its fail-closed contract."""


def check(condition: bool) -> None:
    if not condition:
        raise GateError("clean-host inspection contract failed")


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise GateError("duplicate JSON key")
        result[key] = value
    return result


def parse_json(value: bytes) -> Any:
    try:
        return json.loads(
            value.decode("utf-8", errors="strict"),
            object_pairs_hook=strict_pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(GateError("invalid JSON number")),
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GateError("invalid JSON evidence") from exc


def bounded_docker(
    argv: list[str], timeout: float | None = None
) -> tuple[int, bytes, bytes]:
    check(argv and argv[0] == "docker")
    deadline = time.monotonic() + (TIMEOUT_SECONDS if timeout is None else timeout)
    process = subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    captured = {process.stdout: bytearray(), process.stderr: bytearray()}
    limits = {process.stdout: MAX_STDOUT, process.stderr: MAX_STDERR}
    try:
        for stream in captured:
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise GateError("clean-host inspection timed out")
            if process.poll() is not None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            for key, _ in selector.select(min(remaining, 0.05)):
                stream = key.fileobj
                try:
                    chunk = os.read(stream.fileno(), 128 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(stream)
                    continue
                if len(captured[stream]) + len(chunk) > limits[stream]:
                    raise GateError("clean-host inspection output exceeded its limit")
                captured[stream].extend(chunk)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise GateError("clean-host inspection timed out")
        process.wait(timeout=remaining)
        return (
            process.returncode,
            bytes(captured[process.stdout]),
            bytes(captured[process.stderr]),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GateError("clean-host inspection process failed") from exc
    finally:
        selector.close()
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        process.stdout.close()
        process.stderr.close()


def docker_remove() -> None:
    try:
        bounded_docker(["docker", "rm", "-f", CONTAINER_NAME], timeout=5)
    except (GateError, OSError, subprocess.SubprocessError):
        pass


def docker_image_check(image: str) -> None:
    status, stdout, stderr = bounded_docker(
        ["docker", "image", "inspect", "--format", "{{json .}}", image]
    )
    check(status == 0 and not stderr)
    details = parse_json(stdout)
    check(isinstance(details, dict))
    check(details.get("Os") == "linux")
    check(details.get("Architecture") == "amd64")
    config = details.get("Config")
    check(isinstance(config, dict))
    check(config.get("Volumes") in (None, {}))


def docker_run_argv(image: str) -> list[str]:
    return [
        "docker",
        "run",
        "--platform",
        "linux/amd64",
        "--name",
        CONTAINER_NAME,
        "--network",
        "none",
        "--read-only",
        "--cap-drop",
        "ALL",
        "--security-opt",
        "no-new-privileges=true",
        "--pids-limit",
        "64",
        "--memory",
        "1g",
        "--user",
        "65532:65532",
        "--log-driver",
        "none",
        "--tmpfs",
        "/tmp:rw,nosuid,nodev,noexec,size=64m,mode=1777",
        "--tmpfs",
        "/home/spectra:rw,nosuid,nodev,noexec,size=16m,mode=0700,uid=65532,gid=65532",
        "--entrypoint",
        "/usr/bin/env",
        image,
        "-i",
        "PATH=/usr/local/bin:/usr/bin:/bin",
        "HOME=/home/spectra",
        "LANG=C.UTF-8",
        "PYTHONDONTWRITEBYTECODE=1",
        "/usr/local/bin/python3",
        "/opt/spectra/codex-executor.py",
        "inspect-context",
        "--codex-bin",
        "/usr/local/bin/codex",
    ]


def require_int(value: Any, minimum: int, maximum: int) -> int:
    check(isinstance(value, int) and not isinstance(value, bool))
    check(minimum <= value <= maximum)
    return value


def require_hash(value: Any) -> str:
    check(isinstance(value, str) and SHA256_RE.fullmatch(value) is not None)
    return value


def fingerprint(value: Any) -> dict[str, Any]:
    check(isinstance(value, dict) and set(value) == {"json_type", "bytes", "sha256"})
    check(value["json_type"] in {"null", "boolean", "number", "string", "array", "object", "unknown"})
    return {
        "json_type": value["json_type"],
        "bytes": require_int(value["bytes"], 0, MAX_STDOUT),
        "sha256": require_hash(value["sha256"]),
    }


def text_descriptor(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    check(
        isinstance(value, dict)
        and set(value)
        == {"classification", "bytes", "canonical_bytes", "canonical_sha256"}
    )
    check(
        value["classification"]
        in {
            "sentinel",
            "skills_instructions",
            "permissions_instructions",
            "environment_context",
            "other",
        }
    )
    return {
        "classification": value["classification"],
        "bytes": require_int(value["bytes"], 0, MAX_STDOUT),
        "canonical_bytes": require_int(value["canonical_bytes"], 0, MAX_STDOUT),
        "canonical_sha256": require_hash(value["canonical_sha256"]),
    }


def content_summary(value: Any, expected_index: int) -> dict[str, Any]:
    check(isinstance(value, dict))
    check(require_int(value.get("index"), 0, 31) == expected_index)
    if value.get("shape") == "non-object":
        check(set(value) == {"index", "shape", "value"})
        return {
            "index": expected_index,
            "shape": "non-object",
            "value": fingerprint(value["value"]),
        }
    check(value.get("shape") == "object")
    check(
        set(value)
        == {
            "index",
            "shape",
            "known_keys",
            "unknown_key_count",
            "unknown_values",
            "type",
            "text",
        }
    )
    known = value["known_keys"]
    check(
        isinstance(known, list)
        and known == sorted(set(known))
        and all(item in {"text", "type"} for item in known)
    )
    unknown_count = require_int(value["unknown_key_count"], 0, 64)
    unknown = value["unknown_values"]
    check((unknown_count == 0) == (unknown is None))
    check(value["type"] in {"input_text", "other"})
    return {
        "index": expected_index,
        "shape": "object",
        "known_keys": list(known),
        "unknown_key_count": unknown_count,
        "unknown_values": None if unknown is None else fingerprint(unknown),
        "type": value["type"],
        "text": text_descriptor(value["text"]),
    }


def message_summary(value: Any, expected_index: int) -> dict[str, Any]:
    check(isinstance(value, dict))
    check(require_int(value.get("index"), 0, 31) == expected_index)
    if value.get("shape") == "non-object":
        check(set(value) == {"index", "shape", "value"})
        return {
            "index": expected_index,
            "shape": "non-object",
            "value": fingerprint(value["value"]),
        }
    check(value.get("shape") == "object")
    required = {
        "index",
        "shape",
        "known_keys",
        "unknown_key_count",
        "unknown_values",
        "role",
        "type",
        "envelope_metadata",
        "content",
    }
    check(set(value) in (required, required | {"content_value"}))
    known = value["known_keys"]
    check(
        isinstance(known, list)
        and known == sorted(set(known))
        and all(
            item
            in {
                "content",
                "id",
                "internal_chat_message_metadata_passthrough",
                "role",
                "type",
            }
            for item in known
        )
    )
    unknown_count = require_int(value["unknown_key_count"], 0, 64)
    unknown = value["unknown_values"]
    check((unknown_count == 0) == (unknown is None))
    metadata_expected = any(
        key in known for key in ("id", "internal_chat_message_metadata_passthrough")
    )
    metadata = value["envelope_metadata"]
    check(metadata_expected == (metadata is not None))
    check(value["role"] in {"developer", "user", "other"})
    check(value["type"] in {"message", "other"})
    check(isinstance(value["content"], list) and len(value["content"]) <= 32)
    has_content_value = "content_value" in value
    check(("content" in known) or has_content_value)
    check(not has_content_value or not value["content"])
    result: dict[str, Any] = {
        "index": expected_index,
        "shape": "object",
        "known_keys": list(known),
        "unknown_key_count": unknown_count,
        "unknown_values": None if unknown is None else fingerprint(unknown),
        "role": value["role"],
        "type": value["type"],
        "envelope_metadata": None if metadata is None else fingerprint(metadata),
        "content": [
            content_summary(item, index)
            for index, item in enumerate(value["content"])
        ],
    }
    if has_content_value:
        result["content_value"] = fingerprint(value["content_value"])
    return result


def bytes_hash(value: Any) -> dict[str, Any]:
    check(isinstance(value, dict) and set(value) == {"bytes", "sha256"})
    return {
        "bytes": require_int(value["bytes"], 0, MAX_STDOUT),
        "sha256": require_hash(value["sha256"]),
    }


def sanitize_report(report: Any, expected_hash: str) -> dict[str, Any]:
    expected = {
        "version",
        "operation",
        "status",
        "codex",
        "context",
        "codex_cli_debug_subcommand_invoked",
        "authentication_supplied",
        "provider_subcommand_invoked",
        "project_content_supplied",
    }
    check(isinstance(report, dict) and set(report) == expected)
    check(
        isinstance(report["version"], str)
        and re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", report["version"])
        is not None
    )
    check(report["operation"] == "inspect-context")
    check(report["status"] == "inspected")
    check(report["codex_cli_debug_subcommand_invoked"] is True)
    check(report["authentication_supplied"] is False)
    check(report["provider_subcommand_invoked"] is False)
    check(report["project_content_supplied"] is False)

    codex = report["codex"]
    check(
        isinstance(codex, dict)
        and set(codex) == {"version_descriptor", "size", "sha256"}
    )
    check(require_int(codex["size"], 1, MAX_BINARY_SIZE) > 0)
    check(require_hash(codex["sha256"]) == expected_hash)
    version = codex["version_descriptor"]
    check(isinstance(version, dict) and set(version) == {"stdout", "stderr"})

    context = report["context"]
    context_keys = {
        "diagnostic_version",
        "message_count",
        "messages",
        "content_boundary_sha256",
        "metadata_boundary_sha256",
        "system_skills",
        "raw_content_emitted",
    }
    check(isinstance(context, dict) and set(context) == context_keys)
    check(context["diagnostic_version"] == "redacted-prompt-context-v1")
    check(context["raw_content_emitted"] is False)
    message_count = require_int(context["message_count"], 0, 32)
    check(
        isinstance(context["messages"], list)
        and len(context["messages"]) == message_count
    )
    messages = [
        message_summary(item, index)
        for index, item in enumerate(context["messages"])
    ]

    content_boundary = []
    metadata_boundary = []
    for message in messages:
        if message["shape"] == "non-object":
            content_boundary.append(message)
            continue
        content_boundary_entry = {
            "index": message["index"],
            "role": message["role"],
            "type": message["type"],
            "content": message["content"],
        }
        if "content_value" in message:
            content_boundary_entry["content_value"] = message["content_value"]
        content_boundary.append(content_boundary_entry)
        metadata_boundary.append(
            {
                "index": message["index"],
                "known_keys": message["known_keys"],
                "unknown_values": message["unknown_values"],
                "envelope_metadata": message["envelope_metadata"],
            }
        )
    check(
        require_hash(context["content_boundary_sha256"])
        == hashlib.sha256(canonical_json(content_boundary)).hexdigest()
    )
    check(
        require_hash(context["metadata_boundary_sha256"])
        == hashlib.sha256(canonical_json(metadata_boundary)).hexdigest()
    )

    skills = context["system_skills"]
    check(
        isinstance(skills, dict)
        and set(skills)
        == {
            "system_tree_present",
            "observed_safe_names",
            "unknown_name_count",
            "unknown_names_sha256",
        }
    )
    check(isinstance(skills["system_tree_present"], bool))
    names = skills["observed_safe_names"]
    check(
        isinstance(names, list)
        and names == sorted(set(names))
        and all(name in KNOWN_SKILLS for name in names)
    )
    unknown_name_count = require_int(skills["unknown_name_count"], 0, 1024)
    unknown_names_hash = skills["unknown_names_sha256"]
    check((unknown_name_count == 0) == (unknown_names_hash is None))
    if unknown_names_hash is not None:
        unknown_names_hash = require_hash(unknown_names_hash)
    if not skills["system_tree_present"]:
        check(not names and unknown_name_count == 0 and unknown_names_hash is None)

    return {
        "version": report["version"],
        "operation": "inspect-context",
        "status": "inspected",
        "codex": {
            "version_descriptor": {
                "stdout": bytes_hash(version["stdout"]),
                "stderr": bytes_hash(version["stderr"]),
            },
            "size": codex["size"],
            "sha256": codex["sha256"],
        },
        "context": {
            "diagnostic_version": context["diagnostic_version"],
            "message_count": message_count,
            "messages": messages,
            "content_boundary_sha256": context["content_boundary_sha256"],
            "metadata_boundary_sha256": context["metadata_boundary_sha256"],
            "system_skills": {
                "system_tree_present": skills["system_tree_present"],
                "observed_safe_names": list(names),
                "unknown_name_count": unknown_name_count,
                "unknown_names_sha256": unknown_names_hash,
            },
            "raw_content_emitted": False,
        },
        "codex_cli_debug_subcommand_invoked": True,
        "authentication_supplied": False,
        "provider_subcommand_invoked": False,
        "project_content_supplied": False,
    }


def secure_write(path: Path, value: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as output:
            output.write(value)
            output.flush()
            os.fsync(output.fileno())
    finally:
        os.close(descriptor)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(allow_abbrev=False)
    result.add_argument("--image", required=True)
    result.add_argument("--expected-sha256", required=True)
    result.add_argument("--evidence-root", required=True)
    result.add_argument("--codex-version", required=True)
    result.add_argument("--workflow-commit", required=True)
    result.add_argument("--runner-os", required=True, choices=("Linux",))
    result.add_argument("--runner-arch", required=True, choices=("X64",))
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        check(IMAGE_RE.fullmatch(args.image) is not None)
        check(SHA256_RE.fullmatch(args.expected_sha256) is not None)
        check(VERSION_RE.fullmatch(args.codex_version) is not None)
        check(COMMIT_RE.fullmatch(args.workflow_commit) is not None)
        evidence = Path(args.evidence_root)
        check(evidence.is_absolute() and not evidence.exists())
        evidence.mkdir(mode=0o700, parents=True)
        atexit.register(docker_remove)
        docker_image_check(args.image)
        docker_remove()
        status, stdout, stderr = bounded_docker(docker_run_argv(args.image))
        check(status == 0 and not stderr)
        report = parse_json(stdout)
        sanitized = sanitize_report(report, args.expected_sha256)
        report_bytes = (
            json.dumps(sanitized, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
        ).encode("utf-8")
        provenance = {
            "schema_version": "spectra-clean-host-evidence-v2",
            "workflow_commit": args.workflow_commit,
            "runner_os": args.runner_os,
            "runner_arch": args.runner_arch,
            "codex_version_requested": args.codex_version,
            "codex_binary_sha256_expected": args.expected_sha256,
            "runtime_network": "none",
            "authorization_effect": "evidence-only",
            "report_sha256": hashlib.sha256(report_bytes).hexdigest(),
        }
        provenance_bytes = (
            json.dumps(provenance, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
        ).encode("utf-8")
        secure_write(evidence / "inspect-context.json", report_bytes)
        secure_write(evidence / "provenance.json", provenance_bytes)
        return 0
    except (GateError, OSError, subprocess.SubprocessError):
        return 2
    finally:
        docker_remove()


if __name__ == "__main__":
    raise SystemExit(main())
