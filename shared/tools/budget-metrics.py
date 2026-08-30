#!/usr/bin/env python3
"""Atomically maintain moderator-owned Spectra budget metrics."""

import argparse
import json
import math
import os
import sys
import tempfile
from pathlib import Path


COUNT_FIELDS = ("agent_spawns", "model_calls", "rounds", "finalization_model_calls_used")
GAUGE_FIELDS = ("output_kb", "wall_seconds")
ZERO_METRICS = {
    "agent_spawns": 0,
    "model_calls": 0,
    "finalization_model_calls_used": 0,
    "rounds": 0,
    "output_kb": 0,
    "wall_seconds": 0,
}


class MetricsError(Exception):
    """Expected user-facing metrics error."""


def emit(data):
    print(json.dumps(data, sort_keys=True))


def validate_nonnegative_int(value, field):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise MetricsError(f"{field} must be a non-negative integer")


def validate_nonnegative_number(value, field):
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value < 0
    ):
        raise MetricsError(f"{field} must be a non-negative number")


def validate_metrics(data):
    if not isinstance(data, dict):
        raise MetricsError("budget-metrics.json must contain a JSON object")
    missing = sorted(set(COUNT_FIELDS + GAUGE_FIELDS) - set(data))
    if missing:
        raise MetricsError(f"budget-metrics.json missing fields: {', '.join(missing)}")
    for field in COUNT_FIELDS:
        validate_nonnegative_int(data[field], field)
    for field in GAUGE_FIELDS:
        validate_nonnegative_number(data[field], field)
    if data["finalization_model_calls_used"] > data["model_calls"]:
        raise MetricsError("finalization_model_calls_used cannot exceed model_calls")
    return {field: data[field] for field in ZERO_METRICS}


def resolve_session_dir(raw_path):
    sessions_root = Path(
        os.environ.get("SPECTRA_SESSION_ROOT", str(Path.home() / ".spectra" / "sessions"))
    )
    session_path = Path(raw_path)
    if session_path.is_symlink():
        raise MetricsError(f"session directory must not be a symlink: {session_path}")
    try:
        root = sessions_root.resolve(strict=True)
        session_dir = session_path.resolve(strict=True)
    except (FileNotFoundError, OSError) as exc:
        raise MetricsError(f"session directory could not be resolved: {exc}") from None
    if not session_dir.is_dir():
        raise MetricsError(f"session directory not found: {session_dir}")
    if root not in session_dir.parents:
        raise MetricsError(f"session directory is outside the Spectra sessions root: {session_dir}")
    return session_dir


def load_metrics(path):
    if path.is_symlink():
        raise MetricsError("budget-metrics.json must not be a symlink")
    try:
        with path.open("r", encoding="utf-8") as handle:
            return validate_metrics(json.load(handle))
    except FileNotFoundError:
        raise MetricsError(f"budget-metrics.json not found: {path}") from None
    except json.JSONDecodeError as exc:
        raise MetricsError(f"budget-metrics.json is malformed JSON: {exc}") from None
    except OSError as exc:
        raise MetricsError(f"budget-metrics.json could not be read: {exc}") from None


def atomic_write(path, data):
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=str(path.parent),
            prefix=".budget-metrics.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(data, handle, sort_keys=True, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary_path), str(path))
        temporary_path = None
    except OSError as exc:
        raise MetricsError(f"budget-metrics.json could not be written: {exc}") from None
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except OSError:
                pass


def command_init(args):
    session_dir = resolve_session_dir(args.session_dir)
    path = session_dir / "budget-metrics.json"
    if path.is_symlink():
        raise MetricsError("budget-metrics.json must not be a symlink")
    if path.exists():
        metrics = load_metrics(path)
    else:
        metrics = dict(ZERO_METRICS)
        atomic_write(path, metrics)
    emit(metrics)


def command_record(args):
    session_dir = resolve_session_dir(args.session_dir)
    path = session_dir / "budget-metrics.json"
    metrics = load_metrics(path)

    additions = {
        "agent_spawns": args.add_agent_spawns,
        "model_calls": args.add_model_calls,
        "rounds": args.add_rounds,
        "finalization_model_calls_used": args.add_finalization_model_calls,
    }
    for field, value in additions.items():
        validate_nonnegative_int(value, field)
    if args.add_finalization_model_calls > args.add_model_calls:
        raise MetricsError(
            "add-finalization-model-calls cannot exceed add-model-calls in the same record"
        )
    for field, value in additions.items():
        metrics[field] += value

    for field, value in (("output_kb", args.set_output_kb), ("wall_seconds", args.set_wall_seconds)):
        if value is None:
            continue
        validate_nonnegative_number(value, field)
        if value < metrics[field]:
            raise MetricsError(f"{field} cannot decrease from {metrics[field]} to {value}")
        metrics[field] = value

    validate_metrics(metrics)
    atomic_write(path, metrics)
    emit(metrics)


def nonnegative_int(value):
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("value must be a non-negative integer") from exc
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be a non-negative integer")
    return parsed


def nonnegative_number(value):
    try:
        parsed = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("value must be a non-negative number") from exc
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be a non-negative number")
    return parsed


def build_parser():
    parser = argparse.ArgumentParser(description="Spectra budget metrics updater")
    commands = parser.add_subparsers(dest="command", required=True)

    initialize = commands.add_parser("init", help="Create or validate a zero metrics snapshot")
    initialize.add_argument("session_dir")
    initialize.set_defaults(func=command_init)

    record = commands.add_parser("record", help="Record completed work in a metrics snapshot")
    record.add_argument("session_dir")
    record.add_argument("--add-agent-spawns", type=nonnegative_int, default=0)
    record.add_argument("--add-model-calls", type=nonnegative_int, default=0)
    record.add_argument("--add-rounds", type=nonnegative_int, default=0)
    record.add_argument("--set-output-kb", type=nonnegative_number)
    record.add_argument("--set-wall-seconds", type=nonnegative_number)
    record.add_argument("--add-finalization-model-calls", type=nonnegative_int, default=0)
    record.set_defaults(func=command_record)
    return parser


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except MetricsError as exc:
        print(f"budget-metrics: {exc}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
