#!/usr/bin/env python3
"""Summarize Spectra session budgets and aggregate local calibration data."""

import argparse
import hashlib
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path


SUMMARY_VERSION = "1.1.0"
SUPPORTED_SUMMARY_VERSIONS = {"1.0.0", SUMMARY_VERSION}
REPORT_VERSION = "1.0.0"
CALIBRATION_VERSION = "1.0.0"
CALIBRATION_MIN_SESSIONS = 20
CALIBRATION_MIN_SPAN_DAYS = 7
CALIBRATION_HEADROOM = 0.15
SKILLS = (
    "deep-design",
    "decision-board",
    "peer-review",
    "trust-layer",
    "coherence-monitor",
)
LEVEL_ORDER = {"none": 0, "warning": 1, "caution": 2, "critical": 3}
METRIC_LIMITS = {
    "agent_spawns": "max_agent_spawns",
    "model_calls": "max_model_calls",
    "rounds": "max_rounds",
    "output_kb": "max_output_kb",
    "wall_seconds": "max_wall_seconds",
}


def canonical_json(value):
    """Return a stable JSON representation suitable for local fingerprints."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def policy_fingerprint(policy):
    digest = hashlib.sha256(canonical_json(policy).encode("utf-8")).hexdigest()
    return f"sha256:{digest}"


def policy_catalog_path():
    return Path(__file__).resolve().parent.parent / "schemas" / "budget-policies.json"


def current_policies():
    """Load valid current policies keyed by skill/tier without mutating anything."""
    caveats = []
    catalog = load_json(policy_catalog_path(), caveats, "budget-policies.json")
    if not isinstance(catalog, dict) or not isinstance(catalog.get("policies"), list):
        return {}, ["current_policy_catalog_invalid"]
    policies = {}
    for policy in catalog["policies"]:
        if not valid_policy(policy):
            continue
        key = (policy.get("skill"), policy.get("tier"))
        if key[0] in SKILLS and isinstance(key[1], str):
            policies[key] = policy
    return policies, []


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path, caveats, label):
    if path.is_symlink():
        caveats.append({"artifact": label, "issue": "symlink_not_allowed"})
        return None
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        caveats.append({"artifact": label, "issue": type(exc).__name__})
        return None


def read_events(session_dir, caveats):
    events = []
    event_files = sorted(session_dir.glob("*.jsonl"))
    for event_file in event_files:
        if event_file.is_symlink():
            caveats.append({"artifact": event_file.name, "issue": "symlink_not_allowed"})
            continue
        try:
            with event_file.open("r", encoding="utf-8") as handle:
                for line_number, line in enumerate(handle, 1):
                    if not line.strip():
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        caveats.append(
                            {
                                "artifact": event_file.name,
                                "issue": "malformed_jsonl",
                                "line": line_number,
                            }
                        )
                        continue
                    if isinstance(event, dict):
                        events.append(event)
        except OSError as exc:
            caveats.append({"artifact": event_file.name, "issue": type(exc).__name__})
    return events, bool(event_files)


def event_of_type(events, event_type, last=False):
    matches = [event for event in events if event.get("type") == event_type]
    if not matches:
        return None
    return matches[-1] if last else matches[0]


def metric_value(data, *names):
    if not isinstance(data, dict):
        return 0
    for name in names:
        if name in data:
            return data[name]
    nested = data.get("metrics")
    if isinstance(nested, dict):
        for name in names:
            if name in nested:
                return nested[name]
    return 0


def optional_metric_value(data, *names):
    if not isinstance(data, dict):
        return None
    for name in names:
        if name in data:
            return data[name]
    nested = data.get("metrics")
    if isinstance(nested, dict):
        for name in names:
            if name in nested:
                return nested[name]
    return None


def normalized_metrics(data, caveats, require_complete=False):
    if not isinstance(data, dict):
        return None
    if require_complete:
        missing = sorted(set(METRIC_LIMITS) - set(data))
        if missing:
            caveats.append(
                {
                    "artifact": "budget-metrics.json",
                    "issue": "missing_fields",
                    "fields": missing,
                }
            )
            return None
    metrics = {
        "agent_spawns": metric_value(data, "agent_spawns", "agents_spawned"),
        "model_calls": metric_value(data, "model_calls", "model_calls_used"),
        "rounds": metric_value(data, "rounds", "rounds_completed"),
        "output_kb": metric_value(data, "output_kb", "cumulative_output_kb"),
        "wall_seconds": metric_value(data, "wall_seconds", "elapsed_seconds", "duration_seconds"),
    }
    finalization_calls = optional_metric_value(data, "finalization_model_calls_used")
    for field in ("agent_spawns", "model_calls", "rounds"):
        value = metrics[field]
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            caveats.append({"artifact": "budget-metrics.json", "issue": f"invalid_{field}"})
            return None
    for field in ("output_kb", "wall_seconds"):
        value = metrics[field]
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or value < 0
        ):
            caveats.append({"artifact": "budget-metrics.json", "issue": f"invalid_{field}"})
            return None
    if finalization_calls is not None:
        if (
            isinstance(finalization_calls, bool)
            or not isinstance(finalization_calls, int)
            or finalization_calls < 0
            or finalization_calls > metrics["model_calls"]
        ):
            caveats.append(
                {"artifact": "budget-metrics.json", "issue": "invalid_finalization_model_calls_used"}
            )
            return None
        metrics["finalization_model_calls_used"] = finalization_calls
    return metrics


def valid_policy(policy):
    if not isinstance(policy, dict) or not isinstance(policy.get("limits"), dict):
        return False
    limits = policy["limits"]
    required = set(METRIC_LIMITS.values()) | {
        "default_core_agents",
        "default_specialists",
        "included_rounds",
        "reserved_finalization_calls",
    }
    if not required.issubset(limits):
        return False
    return all(
        not isinstance(limits[field], bool)
        and isinstance(limits[field], (int, float))
        and limits[field] >= 0
        for field in required
    )


def derive_plan(policy, session_start):
    existing = session_start.get("dry_run_estimate") if isinstance(session_start, dict) else None
    if isinstance(existing, dict):
        return existing
    if not valid_policy(policy):
        return None
    limits = policy["limits"]
    planning = policy.get("planning", {})
    core = limits["default_core_agents"]
    specialists = limits["default_specialists"]
    rounds = limits["included_rounds"]
    active = core + specialists
    final_cycles = planning.get("final_position_cycles", 0)
    fixed_calls = planning.get("fixed_model_calls", 0)
    spawns = active + active * rounds + active * final_cycles
    model_calls = fixed_calls + spawns + limits["reserved_finalization_calls"]
    return {
        "planned_core_agents": core,
        "planned_specialists": specialists,
        "planned_active_agents": active,
        "planned_rounds": rounds,
        "planned_agent_spawns": spawns,
        "planned_model_calls": model_calls,
        "reserved_finalization_calls": limits["reserved_finalization_calls"],
        "estimated_wall_seconds": limits["max_wall_seconds"],
        "estimated_output_kb": limits["max_output_kb"],
        "optional_phases": policy.get("optional_phases", {}),
    }


def evaluate(policy, observed):
    if not valid_policy(policy) or observed is None:
        return None
    limits = policy["limits"]
    ratios = {}
    remaining = {}
    for metric, limit_field in METRIC_LIMITS.items():
        used = observed[metric]
        limit = limits[limit_field]
        ratios[metric] = 1.0 if limit == 0 and used > 0 else (used / limit if limit else 0.0)
        remaining[metric] = max(0, limit - used)
    reserved = limits["reserved_finalization_calls"]
    remaining_after_reserve = limits["max_model_calls"] - observed["model_calls"] - reserved
    remaining["model_calls_after_finalization_reserve"] = max(0, remaining_after_reserve)
    maximum = max(ratios.values()) if ratios else 0.0
    if maximum >= 1.0:
        level, action = "critical", "force_final"
    elif maximum >= 0.8:
        level, action = "caution", "skip_optional"
    elif maximum >= 0.6:
        level, action = "warning", "checkpoint_written"
    else:
        level, action = "none", "logged"
    return {
        "final_level": level,
        "final_action": action,
        "max_ratio": round(maximum, 4),
        "ratios": {name: round(value, 4) for name, value in ratios.items()},
        "remaining": remaining,
    }


def highest_level(events, final_level):
    levels = [final_level] if final_level in LEVEL_ORDER else []
    for event in events:
        if event.get("type") != "context_budget_status":
            continue
        level = event.get("active_threshold", event.get("level"))
        if level in LEVEL_ORDER:
            levels.append(level)
    return max(levels, key=LEVEL_ORDER.get) if levels else None


def summarize_session(session_dir, state_override=None, quality_override=None):
    session_dir = Path(session_dir)
    caveats = []
    policy_path = session_dir / "budget-policy.json"
    metrics_path = session_dir / "budget-metrics.json"
    policy = load_json(policy_path, caveats, "budget-policy.json")
    metrics_data = load_json(metrics_path, caveats, "budget-metrics.json")
    events, events_present = read_events(session_dir, caveats)
    start = event_of_type(events, "session_start") or {}
    end = event_of_type(events, "session_end", last=True)
    emergency = event_of_type(events, "emergency_checkpoint", last=True)
    budget_events = [event for event in events if event.get("type") == "context_budget_status"]

    policy_valid = valid_policy(policy)
    if policy_path.is_file() and not policy_valid:
        if not any(item.get("artifact") == "budget-policy.json" for item in caveats):
            caveats.append({"artifact": "budget-policy.json", "issue": "invalid_policy"})

    observed = (
        normalized_metrics(metrics_data, caveats, require_complete=True)
        if metrics_data is not None
        else None
    )
    metrics_valid = observed is not None if metrics_path.is_file() else False
    if observed is None and budget_events:
        observed = normalized_metrics(budget_events[-1].get("metrics", {}), caveats)

    evaluation = evaluate(policy, observed)
    final_level = evaluation["final_level"] if evaluation else None
    if evaluation is not None:
        evaluation["highest_level_seen"] = highest_level(events, final_level)

    overshoots = []
    if policy_valid and observed is not None:
        for metric, limit_field in METRIC_LIMITS.items():
            limit = policy["limits"][limit_field]
            if observed[metric] > limit:
                overshoots.append(
                    {
                        "name": metric,
                        "limit": limit,
                        "observed": observed[metric],
                        "overshoot_by": observed[metric] - limit,
                    }
                )

    blocked_actions = 0
    controls = set()
    for event in budget_events:
        proposed = event.get("proposed_action")
        if isinstance(proposed, dict) and proposed.get("allowed") is False:
            blocked_actions += 1
        for control in event.get("controls_active", []):
            if isinstance(control, str):
                controls.add(control)

    reserve = {
        "reserved": 0,
        "usage_known": False,
        "used": None,
        "remaining": None,
        "encroached": False,
        "breached": None,
    }
    if policy_valid:
        reserved = policy["limits"]["reserved_finalization_calls"]
        calls = observed["model_calls"] if observed else 0
        nonfinalization_ceiling = policy["limits"]["max_model_calls"] - reserved
        finalization_used = observed.get("finalization_model_calls_used") if observed else None
        reserve = {
            "reserved": reserved,
            "usage_known": finalization_used is not None,
            "used": finalization_used,
            "remaining": max(0, reserved - finalization_used)
            if finalization_used is not None
            else None,
            "encroached": calls > nonfinalization_ceiling,
            "breached": (
                calls - finalization_used > nonfinalization_ceiling
                or finalization_used > reserved
                or calls > policy["limits"]["max_model_calls"]
            )
            if finalization_used is not None
            else None,
        }

    quality = quality_override or (end.get("quality") if isinstance(end, dict) else None)
    legacy = not policy_path.is_file() and not metrics_path.is_file()
    malformed_budget = (policy_path.is_file() and not policy_valid) or (
        metrics_path.is_file() and not metrics_valid
    )
    if malformed_budget:
        state = "invalid"
    elif quality == "interrupted" or emergency is not None:
        state = "interrupted"
    elif legacy:
        state = "legacy"
    elif end is not None:
        state = "complete"
    else:
        state = "active"
    if state_override and not malformed_budget:
        state = state_override

    session_id = start.get("session_id") or (end or {}).get("session_id") or session_dir.name
    skill = (policy or {}).get("skill") or start.get("skill") or session_dir.parent.name
    tier = (policy or {}).get("tier") or start.get("tier")
    return {
        "summary_version": SUMMARY_VERSION,
        "session_id": session_id,
        "skill": skill,
        "tier": tier,
        "generated_at": utc_now(),
        "state": state,
        "quality": quality,
        "compatibility": {
            "budget_policy_present": policy_path.is_file(),
            "budget_policy_valid": policy_valid,
            "budget_metrics_present": metrics_path.is_file(),
            "budget_metrics_valid": metrics_valid,
            "context_budget_events_present": bool(budget_events),
            "event_log_present": events_present,
            "legacy_fallback_used": legacy or malformed_budget,
            "caveats": caveats,
        },
        "planned": derive_plan(policy, start),
        "observed": observed,
        "evaluation": evaluation,
        "outcomes": {
            "overshoot_fields": overshoots,
            "blocked_actions_count": blocked_actions,
            "controls_activated": sorted(controls),
            "finalization_reserve": reserve,
        },
        "calibration_source": {
            "policy_fingerprint": policy_fingerprint(policy) if policy_valid else None,
            "policy_snapshot": policy if policy_valid else None,
        },
    }


def stored_or_live_summary(session_dir):
    summary_path = session_dir / "budget-summary.json"
    if not summary_path.is_file():
        return summarize_session(session_dir)
    caveats = []
    stored = load_json(summary_path, caveats, "budget-summary.json")
    if valid_stored_summary(stored):
        return stored
    live = summarize_session(session_dir)
    live["state"] = "invalid"
    live["compatibility"]["caveats"].append(
        {"artifact": "budget-summary.json", "issue": "invalid_summary"}
    )
    return live


def valid_stored_summary(summary):
    if not isinstance(summary, dict) or summary.get("summary_version") not in SUPPORTED_SUMMARY_VERSIONS:
        return False
    if not isinstance(summary.get("session_id"), str) or summary.get("skill") not in SKILLS:
        return False
    if summary.get("state") not in {"complete", "interrupted", "active", "legacy", "invalid"}:
        return False
    compatibility = summary.get("compatibility")
    if not isinstance(compatibility, dict) or any(
        not isinstance(compatibility.get(field), bool)
        for field in ("budget_policy_present", "budget_policy_valid")
    ):
        return False
    observed = summary.get("observed")
    if observed is not None:
        if not isinstance(observed, dict) or not set(METRIC_LIMITS).issubset(observed):
            return False
        if any(
            isinstance(observed[metric], bool)
            or not isinstance(observed[metric], int)
            or observed[metric] < 0
            for metric in ("agent_spawns", "model_calls", "rounds")
        ):
            return False
        if any(
            isinstance(observed[metric], bool)
            or not isinstance(observed[metric], (int, float))
            or not math.isfinite(observed[metric])
            or observed[metric] < 0
            for metric in ("output_kb", "wall_seconds")
        ):
            return False
        finalization_calls = observed.get("finalization_model_calls_used")
        if finalization_calls is not None and (
            isinstance(finalization_calls, bool)
            or not isinstance(finalization_calls, int)
            or finalization_calls < 0
            or finalization_calls > observed["model_calls"]
        ):
            return False
    evaluation = summary.get("evaluation")
    if evaluation is not None:
        if not isinstance(evaluation, dict):
            return False
        for field in ("final_level", "highest_level_seen"):
            if evaluation.get(field) not in LEVEL_ORDER:
                return False
        if not isinstance(evaluation.get("max_ratio"), (int, float)):
            return False
    if summary.get("summary_version") == SUMMARY_VERSION:
        source = summary.get("calibration_source")
        if not isinstance(source, dict):
            return False
        snapshot = source.get("policy_snapshot")
        fingerprint = source.get("policy_fingerprint")
        if snapshot is not None and (
            not valid_policy(snapshot) or fingerprint != policy_fingerprint(snapshot)
        ):
            return False
        if snapshot is None and fingerprint is not None:
            return False
    return True


def positive_int(value):
    try:
        result = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("limit must be a positive integer") from exc
    if result <= 0:
        raise argparse.ArgumentTypeError("limit must be a positive integer")
    return result


def discover_sessions(root, skill):
    root = Path(root)
    skills = (skill,) if skill else SKILLS
    sessions = []
    for skill_name in skills:
        skill_dir = root / skill_name
        if not skill_dir.is_dir() or skill_dir.is_symlink():
            continue
        for session_dir in skill_dir.iterdir():
            if not session_dir.is_dir() or session_dir.is_symlink():
                continue
            try:
                modified = session_dir.stat().st_mtime
            except OSError:
                continue
            sessions.append((modified, session_dir))
    return sorted(sessions, key=lambda item: item[0], reverse=True)


def aggregate_report(root, skill, limit):
    discovered = discover_sessions(root, skill)
    summaries = [stored_or_live_summary(path) for _, path in discovered]
    states = {name: 0 for name in ("complete", "interrupted", "active", "legacy", "invalid")}
    levels = {name: 0 for name in ("none", "warning", "caution", "critical", "unknown")}
    observed_totals = {name: 0 for name in METRIC_LIMITS}
    policy_present = 0
    calibration_ready = 0
    for summary in summaries:
        states[summary["state"]] = states.get(summary["state"], 0) + 1
        if summary["compatibility"]["budget_policy_present"]:
            policy_present += 1
        if (
            summary["compatibility"]["budget_policy_valid"]
            and summary.get("observed") is not None
            and summary.get("evaluation") is not None
        ):
            calibration_ready += 1
        evaluation = summary.get("evaluation") or {}
        level = evaluation.get("highest_level_seen") or evaluation.get("final_level") or "unknown"
        levels[level] = levels.get(level, 0) + 1
        observed = summary.get("observed")
        if observed:
            for metric in observed_totals:
                observed_totals[metric] += observed[metric]
    return {
        "report_version": REPORT_VERSION,
        "generated_at": utc_now(),
        "filters": {"skill": skill, "limit": limit},
        "totals": {
            "sessions_discovered": len(summaries),
            "sessions_shown": min(limit, len(summaries)),
            "policy_present": policy_present,
            "calibration_ready": calibration_ready,
            "legacy_or_invalid": states["legacy"] + states["invalid"],
            "states": states,
        },
        "levels": levels,
        "observed_totals": observed_totals,
        "sessions": summaries[:limit],
    }


def print_text(report):
    totals = report["totals"]
    scope = report["filters"]["skill"] or "all skills"
    print("Spectra Budget")
    print()
    print(f"Scope: {scope}")
    print(
        f"Sessions: {totals['sessions_discovered']} discovered, "
        f"{totals['sessions_shown']} shown, {totals['calibration_ready']} calibration-ready"
    )
    states = totals["states"]
    print("States: " + ", ".join(f"{name}={count}" for name, count in states.items()))
    print("Levels: " + ", ".join(f"{name}={count}" for name, count in report["levels"].items()))
    observed = report["observed_totals"]
    print(
        "Observed: "
        f"spawns={observed['agent_spawns']} calls={observed['model_calls']} "
        f"rounds={observed['rounds']} output={observed['output_kb']:.1f}KB "
        f"wall={observed['wall_seconds']:.0f}s"
    )
    if report["sessions"]:
        print()
        print("Recent sessions:")
    for summary in report["sessions"]:
        evaluation = summary.get("evaluation") or {}
        level = evaluation.get("highest_level_seen") or evaluation.get("final_level") or "unknown"
        ratio = evaluation.get("max_ratio")
        ratio_text = f"{ratio:.0%}" if isinstance(ratio, (int, float)) else "n/a"
        print(
            f"  {summary['skill']}  {summary['tier'] or '-'}  {summary['state']}  "
            f"level={level} max={ratio_text}  {summary['session_id']}"
        )


def parse_generated_at(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def nearest_rank(values, quantile):
    """Deterministic nearest-rank quantile; callers provide a non-empty list."""
    ordered = sorted(values)
    return ordered[max(0, math.ceil(quantile * len(ordered)) - 1)]


def metric_statistics(values):
    return {
        "min": min(values),
        "p50": nearest_rank(values, 0.50),
        "p90": nearest_rank(values, 0.90),
        "p95": nearest_rank(values, 0.95),
        "max": max(values),
    }


def calibration_reason(summary):
    """Return a deterministic exclusion reason, or None for a usable v1.1 summary."""
    if not valid_stored_summary(summary):
        return "invalid_summary"
    if summary.get("state") != "complete":
        return f"state_{summary.get('state', 'unknown')}"
    if summary.get("quality") != "Full":
        return "quality_not_full"
    compatibility = summary.get("compatibility")
    required = (
        "budget_policy_present",
        "budget_policy_valid",
        "budget_metrics_present",
        "budget_metrics_valid",
    )
    if not isinstance(compatibility, dict) or any(
        compatibility.get(field) is not True for field in required
    ):
        return "telemetry_not_valid"
    if compatibility.get("legacy_fallback_used") is not False:
        return "legacy_fallback_used"
    if compatibility.get("caveats"):
        return "telemetry_caveats_present"
    if summary.get("observed") is None:
        return "telemetry_not_valid"
    if summary["observed"].get("finalization_model_calls_used") is None:
        return "finalization_telemetry_missing"
    if parse_generated_at(summary.get("generated_at")) is None:
        return "invalid_generated_at"
    if summary.get("summary_version") != SUMMARY_VERSION:
        return "missing_calibration_source"
    source = summary.get("calibration_source")
    snapshot = source.get("policy_snapshot") if isinstance(source, dict) else None
    fingerprint = source.get("policy_fingerprint") if isinstance(source, dict) else None
    if not valid_policy(snapshot) or fingerprint != policy_fingerprint(snapshot):
        return "invalid_calibration_source"
    if snapshot.get("skill") != summary.get("skill") or snapshot.get("tier") != summary.get("tier"):
        return "policy_summary_mismatch"
    return None


def summary_bucket_key(summary):
    source = summary.get("calibration_source") or {}
    return (summary.get("skill"), summary.get("tier"), source.get("policy_fingerprint"))


def material_change(metric, current, candidate):
    minimum = 1 if metric in {"agent_spawns", "model_calls", "rounds"} else (
        5 if metric == "output_kb" else 30
    )
    return current - candidate >= minimum


def candidate_limit(metric, statistics, snapshot):
    """Return a lower-only candidate with a known-workload safety margin."""
    maximum = statistics["max"]
    candidate = math.ceil(maximum * (1 + CALIBRATION_HEADROOM))
    if metric in {"agent_spawns", "model_calls", "rounds"} and maximum > 0:
        candidate = max(candidate, int(maximum) + 1)
    plan = derive_plan(snapshot, {}) or {}
    floors = {
        "agent_spawns": plan.get("planned_agent_spawns", 0),
        "model_calls": max(
            plan.get("planned_model_calls", 0),
            snapshot["limits"]["reserved_finalization_calls"],
        ),
        "rounds": snapshot["limits"]["included_rounds"],
        "output_kb": 0,
        "wall_seconds": 0,
    }
    return max(candidate, floors[metric]), floors[metric]


def calibration_bucket(skill, tier, fingerprint, summaries, current_policy):
    timestamps = [parse_generated_at(summary["generated_at"]) for summary in summaries]
    span_days = (max(timestamps) - min(timestamps)).total_seconds() / 86400 if timestamps else 0
    source_snapshot = summaries[0]["calibration_source"]["policy_snapshot"]
    result = {
        "skill": skill,
        "tier": tier,
        "policy_fingerprint": fingerprint,
        "recommendation_status": "insufficient_evidence",
        "confidence": "none",
        "sample": {
            "eligible_sessions": len(summaries),
            "required_sessions": CALIBRATION_MIN_SESSIONS,
            "span_days": round(span_days, 3),
            "required_span_days": CALIBRATION_MIN_SPAN_DAYS,
        },
        "limits": {},
        "preserved": {
            "reserved_finalization_calls": source_snapshot["limits"]["reserved_finalization_calls"],
            "agent_shape_limits": True,
            "automatic_apply": False,
        },
        "reasons": [],
    }
    if current_policy is None or policy_fingerprint(current_policy) != fingerprint:
        result["recommendation_status"] = "evidence_only"
        result["reasons"].append("current_policy_fingerprint_mismatch")
        return result
    if len(summaries) < CALIBRATION_MIN_SESSIONS:
        result["reasons"].append("minimum_eligible_sessions_not_met")
        return result
    if span_days < CALIBRATION_MIN_SPAN_DAYS:
        result["reasons"].append("minimum_observation_span_not_met")
        return result

    result["confidence"] = "high" if len(summaries) >= 50 and span_days >= 14 else "medium"
    result["recommendation_status"] = "no_change"
    for metric, limit_field in METRIC_LIMITS.items():
        statistics = metric_statistics([summary["observed"][metric] for summary in summaries])
        current = current_policy["limits"][limit_field]
        candidate, floor = candidate_limit(metric, statistics, current_policy)
        decision = "retain"
        recommended = current
        rationale = ["15_percent_headroom_above_historical_max", "no_outlier_trimming"]
        if candidate < current and material_change(metric, current, candidate):
            decision = "reduce"
            recommended = candidate
            result["recommendation_status"] = "manual_review_required"
        elif candidate < current:
            rationale.append("change_below_materiality_threshold")
        else:
            rationale.append("candidate_not_lower_than_current_limit")
        result["limits"][limit_field] = {
            "current": current,
            **statistics,
            "candidate": candidate,
            "safety_floor": floor,
            "recommended": recommended,
            "decision": decision,
            "rationale": rationale,
        }
    return result


def stored_summaries_for_calibration(root, skill=None, tier=None):
    """Read only final, regular summary artifacts; never derive live session state."""
    accepted = []
    excluded = {}
    evidence_only = {}
    discovered = discover_sessions(root, skill)
    loaded = []
    for _, session_dir in discovered:
        summary_path = session_dir / "budget-summary.json"
        caveats = []
        summary = load_json(summary_path, caveats, "budget-summary.json")
        if summary is None:
            reason = "symlink_summary" if caveats else "missing_summary"
            excluded[reason] = excluded.get(reason, 0) + 1
            continue
        if not valid_stored_summary(summary):
            excluded["invalid_summary"] = excluded.get("invalid_summary", 0) + 1
            continue
        if tier and summary.get("tier") != tier:
            continue
        loaded.append((summary, session_dir))

    # A copied session may be discovered twice. Retain the newest finalized summary.
    newest = {}
    for summary, session_dir in loaded:
        timestamp = parse_generated_at(summary.get("generated_at"))
        key = (summary.get("skill"), summary.get("tier"), summary.get("session_id"))
        comparison = (timestamp or datetime.min.replace(tzinfo=timezone.utc), str(session_dir))
        if key not in newest or comparison > newest[key][0]:
            if key in newest:
                excluded["duplicate_session_id"] = excluded.get("duplicate_session_id", 0) + 1
            newest[key] = (comparison, summary)
        else:
            excluded["duplicate_session_id"] = excluded.get("duplicate_session_id", 0) + 1

    for _, summary in newest.values():
        reason = calibration_reason(summary)
        key = summary_bucket_key(summary) if summary.get("summary_version") == SUMMARY_VERSION else (
            summary.get("skill"), summary.get("tier"), None
        )
        if reason is None:
            accepted.append(summary)
        elif reason == "missing_calibration_source":
            evidence_only[key] = evidence_only.get(key, 0) + 1
        else:
            excluded[reason] = excluded.get(reason, 0) + 1
    return accepted, excluded, evidence_only, len(discovered)


def calibration_report(root, skill=None, tier=None):
    policies, catalog_reasons = current_policies()
    summaries, excluded, evidence_only, discovered = stored_summaries_for_calibration(root, skill, tier)
    grouped = {}
    for summary in summaries:
        grouped.setdefault(summary_bucket_key(summary), []).append(summary)
    buckets = []
    for (bucket_skill, bucket_tier, fingerprint), group in sorted(
        grouped.items(), key=lambda item: tuple(str(value) for value in item[0])
    ):
        buckets.append(
            calibration_bucket(bucket_skill, bucket_tier, fingerprint, group, policies.get((bucket_skill, bucket_tier)))
        )
    for (bucket_skill, bucket_tier, fingerprint), count in sorted(
        evidence_only.items(), key=lambda item: tuple(str(value) for value in item[0])
    ):
        buckets.append(
            {
                "skill": bucket_skill,
                "tier": bucket_tier,
                "policy_fingerprint": fingerprint,
                "recommendation_status": "evidence_only",
                "confidence": "none",
                "sample": {"eligible_sessions": 0, "evidence_only_sessions": count},
                "limits": {},
                "preserved": {"automatic_apply": False},
                "reasons": ["missing_calibration_source"],
            }
        )
    return {
        "calibration_version": CALIBRATION_VERSION,
        "generated_at": utc_now(),
        "mode": "recommendation_only",
        "automatic_apply": False,
        "filters": {"skill": skill, "tier": tier},
        "totals": {
            "sessions_discovered": discovered,
            "eligible_sessions": len(summaries),
            "excluded": dict(sorted(excluded.items())),
            "evidence_only_sessions": sum(evidence_only.values()),
        },
        "buckets": buckets,
        "global_reasons": catalog_reasons + [
            "recommendations_are_lower_only",
            "manual_review_required_before_policy_changes",
        ],
    }


def print_calibration_text(report):
    totals = report["totals"]
    print("Spectra Budget Calibration")
    print(
        f"Evidence: {totals['eligible_sessions']} eligible of {totals['sessions_discovered']} discovered; "
        "no policy files changed."
    )
    for bucket in report["buckets"]:
        print(
            f"{bucket['skill']} {bucket['tier'] or '-'}: "
            f"{bucket['recommendation_status']} ({bucket['confidence']})"
        )
        for field, limit in bucket["limits"].items():
            if limit["decision"] == "reduce":
                print(f"  {field}: {limit['current']} -> {limit['recommended']} (manual review)")


def build_parser():
    parser = argparse.ArgumentParser(description="Spectra local budget calibration reports")
    commands = parser.add_subparsers(dest="command", required=True)
    summarize = commands.add_parser("summarize", help="Summarize one session as JSON")
    summarize.add_argument("session_dir")
    summarize.add_argument("--state", choices=("complete", "interrupted"))
    summarize.add_argument("--quality")
    report = commands.add_parser("report", help="Aggregate local session budgets")
    report.add_argument("sessions_root")
    report.add_argument("--skill", choices=SKILLS)
    report.add_argument("--limit", type=positive_int, default=10)
    report.add_argument("--json", action="store_true", dest="as_json")
    calibrate = commands.add_parser(
        "calibrate", help="Generate lower-only local budget recommendations (never writes policy)"
    )
    calibrate.add_argument("sessions_root")
    calibrate.add_argument("--skill", choices=SKILLS)
    calibrate.add_argument("--tier", choices=("quick", "standard", "deep"))
    calibrate.add_argument("--json", action="store_true", dest="as_json")
    return parser


def main():
    args = build_parser().parse_args()
    if args.command == "summarize":
        session_dir = Path(args.session_dir)
        if not session_dir.is_dir():
            print(f"session directory not found: {session_dir}", file=sys.stderr)
            return 1
        print(
            json.dumps(
                summarize_session(session_dir, args.state, args.quality),
                sort_keys=True,
            )
        )
        return 0
    if args.command == "calibrate":
        report = calibration_report(args.sessions_root, args.skill, args.tier)
        if args.as_json:
            print(json.dumps(report, sort_keys=True))
        else:
            print_calibration_text(report)
        return 0
    report = aggregate_report(args.sessions_root, args.skill, args.limit)
    if args.as_json:
        print(json.dumps(report, sort_keys=True))
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
