#!/usr/bin/env python3
"""Codex adapter with inert planning and explicitly approved Quick execution."""
from __future__ import print_function

import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any, Dict, List, Set, Tuple

VERSION = "0.1"
RUNTIME = "codex"
ID_RE = re.compile(r"^[a-z][a-z0-9-]{0,63}$")
SESSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SCHEMA_RE = re.compile(r"^[a-z][a-z0-9-]{0,63}-v[0-9]+$")
ROOTS = set(["workspace", "session", "spectra"])
MODELS = set(["economical", "standard", "frontier"])
EXECUTOR_PATH = Path(__file__).with_name("codex-executor.py")


class ValidationError(ValueError):
    pass


def reject_constant(value):
    raise ValidationError("non-finite JSON constant is forbidden: {0}".format(value))


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError("duplicate JSON key: {0}".format(key))
        result[key] = value
    return result


def reject_non_finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValidationError("non-finite JSON number is forbidden")
    if isinstance(value, dict):
        for item in value.values(): reject_non_finite(item)
    elif isinstance(value, list):
        for item in value: reject_non_finite(item)


def read_json(path_arg):
    path = Path(path_arg)
    try:
        info = path.lstat()
    except FileNotFoundError:
        raise ValidationError("plan does not exist: {0}".format(path))
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValidationError("plan must be a regular non-symlink file")
    if info.st_size > 1048576: raise ValidationError("plan exceeds 1 MiB limit")
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle, object_pairs_hook=reject_duplicates, parse_constant=reject_constant)
    except (OSError, ValueError) as exc:
        raise ValidationError("invalid JSON plan: {0}".format(exc))
    reject_non_finite(data)
    if not isinstance(data, dict): raise ValidationError("plan root must be an object")
    return data


def obj(value, label, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValidationError("{0} must contain exactly: {1}".format(label, ", ".join(sorted(keys))))
    return value


def identifier(value, label, pattern=ID_RE):
    if not isinstance(value, str) or not pattern.fullmatch(value): raise ValidationError("invalid {0}".format(label))
    return value


def integer(value, label, minimum, maximum):
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum or value > maximum:
        raise ValidationError("invalid {0}".format(label))
    return value


def relpath(value, label):
    if not isinstance(value, str) or not value or len(value) > 512: raise ValidationError("invalid {0}".format(label))
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or any(part in ("", ".", "..") for part in parsed.parts) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", value):
        raise ValidationError("unsafe {0}".format(label))
    return value


def anchored(value, label, required_root=None):
    data = obj(value, label, ["root", "path"])
    if data["root"] not in ROOTS or (required_root and data["root"] != required_root):
        raise ValidationError("invalid {0}.root".format(label))
    relpath(data["path"], label + ".path")
    return data


def no_cycles(graph):
    visiting, visited = set(), set()
    def visit(node):
        if node in visiting: raise ValidationError("dependency cycle detected")
        if node not in visited:
            visiting.add(node)
            for dependency in graph[node]: visit(dependency)
            visiting.remove(node); visited.add(node)
    for node in graph: visit(node)


def validate_plan(data):
    root = obj(data, "plan", ["version", "session_id", "workflow", "tier", "phase", "actions"])
    if root["version"] != VERSION: raise ValidationError("unsupported plan version")
    identifier(root["session_id"], "session_id", SESSION_RE); identifier(root["workflow"], "workflow")
    if root["tier"] not in ("quick", "standard", "deep"): raise ValidationError("invalid tier")
    phase = obj(root["phase"], "phase", ["id", "join"]); phase_id = identifier(phase["id"], "phase.id")
    join = obj(phase["join"], "phase.join", ["required_successes", "deadline_seconds", "on_timeout", "cancel_remaining_on_quorum"])
    required = integer(join["required_successes"], "phase.join.required_successes", 1, 1000)
    integer(join["deadline_seconds"], "phase.join.deadline_seconds", 1, 86400)
    if join["on_timeout"] not in ("continue-if-quorum", "fail") or not isinstance(join["cancel_remaining_on_quorum"], bool): raise ValidationError("invalid phase join policy")
    actions = root["actions"]
    if not isinstance(actions, list) or not 1 <= len(actions) <= 1000: raise ValidationError("actions must contain 1 to 1000 entries")
    if required > len(actions): raise ValidationError("phase quorum exceeds action count")
    action_ids, workers, outputs, graph = set(), set(), set(), {}
    for index, item in enumerate(actions):
        label = "actions[{0}]".format(index)
        action = obj(item, label, ["id", "action", "depends_on", "retry", "worker", "execution", "completion", "budget"])
        action_id = identifier(action["id"], label + ".id")
        if action_id in action_ids: raise ValidationError("action ids must be unique")
        action_ids.add(action_id)
        if action["action"] != "spawn": raise ValidationError("action must be spawn")
        deps = action["depends_on"]
        if not isinstance(deps, list) or len(deps) != len(set(deps)): raise ValidationError("depends_on must be a unique array")
        graph[action_id] = [identifier(dep, label + ".depends_on") for dep in deps]
        if action_id in graph[action_id]: raise ValidationError("action cannot depend on itself")
        retry = obj(action["retry"], label + ".retry", ["max_attempts", "backoff_seconds"])
        integer(retry["max_attempts"], "max_attempts", 1, 5); integer(retry["backoff_seconds"], "backoff_seconds", 0, 3600)
        worker = obj(action["worker"], label + ".worker", ["id", "role", "prompt_file", "output_path"])
        worker_id = identifier(worker["id"], "worker.id")
        if worker_id in workers: raise ValidationError("worker ids must be unique")
        workers.add(worker_id); identifier(worker["role"], "worker.role")
        anchored(worker["prompt_file"], "worker.prompt_file", "spectra"); output = anchored(worker["output_path"], "worker.output_path", "session")
        output_key = output["root"] + ":" + output["path"]
        if output_key in outputs: raise ValidationError("worker output paths must be unique")
        outputs.add(output_key)
        execution = obj(action["execution"], label + ".execution", ["model_class", "max_turns", "background", "permissions"])
        if execution["model_class"] not in MODELS: raise ValidationError("invalid model_class")
        integer(execution["max_turns"], "max_turns", 1, 100)
        if not isinstance(execution["background"], bool): raise ValidationError("background must be boolean")
        permissions = obj(execution["permissions"], "permissions", ["read_paths", "write_paths", "network"])
        for name in ("read_paths", "write_paths"):
            paths = permissions[name]
            if not isinstance(paths, list) or not paths: raise ValidationError("{0} must be a non-empty array".format(name))
            keys = []
            for path in paths:
                parsed = anchored(path, name); keys.append(parsed["root"] + ":" + parsed["path"])
            if len(keys) != len(set(keys)): raise ValidationError("{0} must not contain duplicates".format(name))
        if permissions["network"] is not False: raise ValidationError("network must be false for the planning-only adapter")
        completion = obj(action["completion"], "completion", ["kind", "path", "schema"])
        if completion["kind"] != "artifact": raise ValidationError("completion.kind must be artifact")
        completed = anchored(completion["path"], "completion.path", "session")
        if completed != output: raise ValidationError("completion.path must equal worker.output_path")
        identifier(completion["schema"], "completion.schema", SCHEMA_RE)
        budget = obj(action["budget"], "budget", ["add_agent_spawns", "add_model_calls", "phase"])
        if isinstance(budget["add_agent_spawns"], bool) or isinstance(budget["add_model_calls"], bool) or budget["add_agent_spawns"] != 1 or budget["add_model_calls"] != 1:
            raise ValidationError("each spawn must increment agent_spawns and model_calls by one")
        if budget["phase"] != phase_id: raise ValidationError("budget.phase must equal phase.id")
    for action_id, dependencies in graph.items():
        for dependency in dependencies:
            if dependency not in action_ids: raise ValidationError("dependency references unknown action: {0}".format(dependency))
    no_cycles(graph)
    return data


def capabilities():
    return {"version": VERSION, "runtime": RUNTIME, "execution_enabled": True, "supported_operations": ["capabilities", "validate", "render", "dry-run", "inspect-context", "preview", "execute", "doctor"], "capabilities": {"supports_background_workers": True, "supports_nested_workers": False, "supports_structured_output": True, "supports_resume": False, "supports_worktrees": False, "supports_network_control": False, "requires_explicit_execution_profile": True, "isolates_user_home": True, "max_parallelism": 2, "model_classes": ["economical", "standard", "frontier"]}}


def dry_run(plan):
    actions = []
    for action in plan["actions"]:
        execution, worker = action["execution"], action["worker"]
        actions.append({"id": action["id"], "depends_on": action["depends_on"], "retry": action["retry"], "worker_id": worker["id"], "role": worker["role"], "model_class": execution["model_class"], "max_turns": execution["max_turns"], "background": execution["background"], "completion_artifact": action["completion"]["path"], "network": False})
    return {"version": VERSION, "runtime": RUNTIME, "status": "planned", "execution_enabled": False, "session_id": plan["session_id"], "workflow": plan["workflow"], "tier": plan["tier"], "phase": plan["phase"], "project_content_transmitted": False, "codex_invoked": False, "actions": actions}


def safe_write(path_arg, payload):
    path = Path(path_arg)
    if (not path.is_absolute() or ".." in path.parts or path_arg != os.path.normpath(path_arg)
            or path_arg.startswith("//")):
        raise ValidationError("unsafe --out path")
    # Resolve every supplied parent segment ourselves: do not silently traverse a symlink.
    cursor = Path(path.anchor)
    for part in path.parts[1:-1]:
        cursor = cursor / part
        try: info = cursor.lstat()
        except FileNotFoundError: raise ValidationError("--out parent does not exist: {0}".format(cursor))
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode): raise ValidationError("--out parent must not contain symlinks")
    try:
        output_info = path.lstat()
    except FileNotFoundError:
        output_info = None
    except OSError as exc:
        raise ValidationError("cannot inspect --out: {0}".format(exc))
    if output_info is not None and (stat.S_ISLNK(output_info.st_mode) or not stat.S_ISREG(output_info.st_mode)):
        raise ValidationError("--out must be a regular file and not a symlink when it already exists")
    temporary = path.with_name(".{0}.tmp-{1}".format(path.name, os.getpid()))
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True); handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
        os.replace(str(temporary), str(path))
    finally:
        if temporary.exists(): temporary.unlink()


def emit(data): json.dump(data, sys.stdout, indent=2, sort_keys=True); sys.stdout.write("\n")
def usage(): return "usage: codex-runtime.py capabilities | validate <plan> | render <plan> | dry-run <plan> [--out ABSOLUTE_PATH] | inspect-context --codex-bin ABS | preview <plan> --workspace-root ABS --session-root ABS --codex-bin ABS --codex-home ABS [--max-concurrency 1|2] | execute <plan> --workspace-root ABS --session-root ABS --codex-bin ABS --codex-home ABS --approve TOKEN [--max-concurrency 1|2] | doctor"


def doctor():
    requested = os.environ.get("SPECTRA_CODEX_BIN")
    candidate = requested or shutil.which("codex")
    result = {"version": VERSION, "runtime": RUNTIME, "execution_enabled": True,
              "execution_ready": False, "codex_cli_detected": candidate is not None,
              "executor_python_ready": sys.version_info >= (3, 10),
              "executor_python_required": "3.10+",
              "codex_invoked": False, "network": "model-service-only; worker tools request no network"}
    if sys.version_info < (3, 10):
        result.update({"status": "unavailable", "reason": "executable Codex adapter requires Python 3.10+"})
        return result
    if candidate is None:
        result.update({"status": "unavailable", "reason": "no Codex executable configured"})
        return result
    result["codex_path"] = candidate
    try:
        completed = subprocess.run([candidate, "--version"], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        result.update({"status": "unavailable", "reason": "Codex probe failed: {0}".format(exc)})
        return result
    if completed.returncode != 0:
        result.update({"status": "unavailable", "reason": "Codex version probe exited {0}".format(completed.returncode)})
        return result
    result.update({"status": "ready", "execution_ready": True,
                   "codex_version": completed.stdout[:512].decode("utf-8", "replace").strip()})
    return result

def main(argv):
    try:
        if argv == ["capabilities"]: emit(capabilities()); return 0
        if argv == ["doctor"]: emit(doctor()); return 0
        if argv and argv[0] in ("inspect-context", "preview", "execute"):
            if sys.version_info < (3, 10):
                raise ValidationError("executable Codex adapter requires Python 3.10+")
            regular_file = EXECUTOR_PATH.lstat()
            if stat.S_ISLNK(regular_file.st_mode) or not stat.S_ISREG(regular_file.st_mode):
                raise ValidationError("Codex executor must be a regular non-symlink file")
            os.execv(sys.executable, [sys.executable, str(EXECUTOR_PATH)] + argv)
        if len(argv) == 2 and argv[0] in ("validate", "render"):
            plan = validate_plan(read_json(argv[1]))
            emit({"version": VERSION, "runtime": RUNTIME, "status": "valid", "session_id": plan["session_id"], "actions": len(plan["actions"]) } if argv[0] == "validate" else dry_run(plan)); return 0
        if len(argv) in (2, 4) and argv[0] == "dry-run":
            if len(argv) == 4 and argv[2] != "--out": raise ValidationError(usage())
            result = dry_run(validate_plan(read_json(argv[1])))
            if len(argv) == 4: safe_write(argv[3], result)
            emit(result); return 0
        raise ValidationError(usage())
    except (ValidationError, OSError) as exc:
        print("codex-runtime: {0}".format(exc), file=sys.stderr); return 2

if __name__ == "__main__": raise SystemExit(main(sys.argv[1:]))
