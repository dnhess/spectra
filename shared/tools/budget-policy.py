#!/usr/bin/env python3
"""Deterministic Spectra budget policy tool."""

import argparse
import copy
import json
import sys
from pathlib import Path


SKILLS = {
    "deep-design",
    "decision-board",
    "peer-review",
    "trust-layer",
    "coherence-monitor",
}
TIERS = {"quick", "standard", "deep"}
LIMIT_FIELDS = {
    "default_core_agents",
    "max_core_agents",
    "default_specialists",
    "max_specialists",
    "max_active_agents",
    "included_rounds",
    "max_rounds",
    "max_output_kb",
    "max_wall_seconds",
    "max_agent_spawns",
    "max_model_calls",
    "reserved_finalization_calls",
}
OPTIONAL_PHASES = {"research", "composition", "verification"}
FINALIZATION_PHASES = {"final-positions", "synthesis", "verification", "report"}
THRESHOLDS = (
    ("critical", 1.0, "force_final"),
    ("caution", 0.8, "skip_optional"),
    ("warning", 0.6, "checkpoint_written"),
)


class BudgetError(Exception):
    """Expected user-facing budget-policy error."""


def emit(data):
    print(json.dumps(data, sort_keys=True))


def fail(message, code=1):
    emit({"error": message})
    raise SystemExit(code)


def load_json(path, label):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        raise BudgetError(f"{label} not found: {path}") from None
    except json.JSONDecodeError as exc:
        raise BudgetError(f"{label} is malformed JSON: {exc}") from None
    except OSError as exc:
        raise BudgetError(f"{label} could not be read: {exc}") from None


def validate_int(value, field, minimum=0):
    if isinstance(value, bool) or not isinstance(value, int):
        raise BudgetError(f"{field} must be an integer")
    if value < minimum:
        raise BudgetError(f"{field} must be >= {minimum}")


def validate_policy(policy):
    if not isinstance(policy, dict):
        raise BudgetError("policy must be a JSON object")
    for field in ("policy_version", "skill", "tier", "limits", "optional_phases", "model_policy", "planning"):
        if field not in policy:
            raise BudgetError(f"policy missing required field: {field}")
    if not isinstance(policy["policy_version"], str):
        raise BudgetError("policy_version must be a string")
    if not isinstance(policy["skill"], str):
        raise BudgetError("skill must be a string")
    if not isinstance(policy["tier"], str):
        raise BudgetError("tier must be a string")
    if policy["skill"] not in SKILLS:
        raise BudgetError(f"invalid skill: {policy['skill']}")
    if policy["tier"] not in TIERS:
        raise BudgetError(f"invalid tier: {policy['tier']}")

    limits = policy["limits"]
    if not isinstance(limits, dict):
        raise BudgetError("limits must be an object")
    missing_limits = sorted(LIMIT_FIELDS - set(limits))
    if missing_limits:
        raise BudgetError(f"limits missing fields: {', '.join(missing_limits)}")
    for field in LIMIT_FIELDS:
        validate_int(limits[field], f"limits.{field}")

    if limits["default_core_agents"] > limits["max_core_agents"]:
        raise BudgetError("default_core_agents exceeds max_core_agents")
    if limits["default_specialists"] > limits["max_specialists"]:
        raise BudgetError("default_specialists exceeds max_specialists")
    if limits["default_core_agents"] + limits["default_specialists"] > limits["max_active_agents"]:
        raise BudgetError("default active agents exceed max_active_agents")
    if limits["included_rounds"] > limits["max_rounds"]:
        raise BudgetError("included_rounds exceeds max_rounds")
    if limits["reserved_finalization_calls"] > limits["max_model_calls"]:
        raise BudgetError("reserved_finalization_calls exceeds max_model_calls")

    optional_phases = policy["optional_phases"]
    if not isinstance(optional_phases, dict):
        raise BudgetError("optional_phases must be an object")
    missing_phases = sorted(OPTIONAL_PHASES - set(optional_phases))
    if missing_phases:
        raise BudgetError(f"optional_phases missing fields: {', '.join(missing_phases)}")
    for phase in OPTIONAL_PHASES:
        if not isinstance(optional_phases[phase], bool):
            raise BudgetError(f"optional_phases.{phase} must be a boolean")

    model_policy = policy["model_policy"]
    if not isinstance(model_policy, dict):
        raise BudgetError("model_policy must be an object")
    for field in ("default", "cheap_phases", "frontier_phases", "frontier_requires_approval"):
        if field not in model_policy:
            raise BudgetError(f"model_policy missing field: {field}")
    if not isinstance(model_policy["default"], str):
        raise BudgetError("model_policy.default must be a string")
    if not isinstance(model_policy["cheap_phases"], list):
        raise BudgetError("model_policy.cheap_phases must be an array")
    if not isinstance(model_policy["frontier_phases"], list):
        raise BudgetError("model_policy.frontier_phases must be an array")
    if not all(isinstance(phase, str) for phase in model_policy["cheap_phases"]):
        raise BudgetError("model_policy.cheap_phases must contain only strings")
    if not all(isinstance(phase, str) for phase in model_policy["frontier_phases"]):
        raise BudgetError("model_policy.frontier_phases must contain only strings")
    if not isinstance(model_policy["frontier_requires_approval"], bool):
        raise BudgetError("model_policy.frontier_requires_approval must be a boolean")

    planning = policy["planning"]
    if not isinstance(planning, dict):
        raise BudgetError("planning must be an object")
    for field in ("fixed_model_calls", "final_position_cycles"):
        if field not in planning:
            raise BudgetError(f"planning missing field: {field}")
        validate_int(planning[field], f"planning.{field}")


def load_catalog(path):
    catalog = load_json(path, "policy catalog")
    if not isinstance(catalog, dict):
        raise BudgetError("policy catalog must be an object")
    if "policies" not in catalog or not isinstance(catalog["policies"], list):
        raise BudgetError("policy catalog must contain a policies array")
    seen = set()
    for policy in catalog["policies"]:
        validate_policy(policy)
        key = (policy["skill"], policy["tier"])
        if key in seen:
            raise BudgetError(f"duplicate policy for {key[0]}/{key[1]}")
        seen.add(key)
    expected = {(skill, tier) for skill in SKILLS for tier in TIERS}
    missing = sorted(expected - seen)
    if missing:
        pretty = ", ".join(f"{skill}/{tier}" for skill, tier in missing)
        raise BudgetError(f"policy catalog missing policies: {pretty}")
    return catalog


def get_policy(catalog, skill, tier):
    if skill not in SKILLS:
        raise BudgetError(f"invalid skill: {skill}")
    if tier not in TIERS:
        raise BudgetError(f"invalid tier: {tier}")
    for policy in catalog["policies"]:
        if policy["skill"] == skill and policy["tier"] == tier:
            return copy.deepcopy(policy)
    raise BudgetError(f"policy not found: {skill}/{tier}")


def phase_enabled(policy, phase):
    if not phase:
        return True
    return policy["optional_phases"].get(phase, True)


def planned_agent_spawns(policy, core, specialists, rounds):
    planning = policy["planning"]
    active_agents = core + specialists
    final_cycles = planning["final_position_cycles"]
    return active_agents + (active_agents * rounds) + (active_agents * final_cycles)


def planned_model_calls(policy, core, specialists, rounds):
    """Return the complete plan, including calls protected for finalization."""
    return (
        policy["planning"]["fixed_model_calls"]
        + planned_agent_spawns(policy, core, specialists, rounds)
        + policy["limits"]["reserved_finalization_calls"]
    )


def estimate_policy(policy, core=None, specialists=None, rounds=None):
    limits = policy["limits"]
    core = limits["default_core_agents"] if core is None else core
    specialists = limits["default_specialists"] if specialists is None else specialists
    rounds = limits["included_rounds"] if rounds is None else rounds

    for value, field in ((core, "core"), (specialists, "specialists"), (rounds, "rounds")):
        validate_int(value, field)

    violations = []
    if core > limits["max_core_agents"]:
        violations.append("core exceeds max_core_agents")
    if specialists > limits["max_specialists"]:
        violations.append("specialists exceed max_specialists")
    if core + specialists > limits["max_active_agents"]:
        violations.append("active agents exceed max_active_agents")
    if rounds > limits["max_rounds"]:
        violations.append("rounds exceed max_rounds")

    agent_spawns = planned_agent_spawns(policy, core, specialists, rounds)
    model_calls = planned_model_calls(policy, core, specialists, rounds)
    if agent_spawns > limits["max_agent_spawns"]:
        violations.append("planned agent spawns exceed max_agent_spawns")
    if model_calls > limits["max_model_calls"]:
        violations.append("planned model calls exceed max_model_calls")
    if violations:
        raise BudgetError("; ".join(violations))

    return {
        "skill": policy["skill"],
        "tier": policy["tier"],
        "policy_version": policy["policy_version"],
        "planned_core_agents": core,
        "planned_specialists": specialists,
        "planned_active_agents": core + specialists,
        "planned_rounds": rounds,
        "planned_agent_spawns": agent_spawns,
        "planned_model_calls": model_calls,
        "reserved_finalization_calls": limits["reserved_finalization_calls"],
        "estimated_wall_seconds": limits["max_wall_seconds"],
        "estimated_output_kb": limits["max_output_kb"],
        "optional_phases": policy["optional_phases"],
        "model_policy": policy["model_policy"],
        "limits": limits,
    }


def metric_value(metrics, *names):
    for name in names:
        if name in metrics:
            return metrics[name]
    nested = metrics.get("metrics")
    if isinstance(nested, dict):
        for name in names:
            if name in nested:
                return nested[name]
    return 0


def normalize_metrics(metrics):
    if not isinstance(metrics, dict):
        raise BudgetError("metrics must be a JSON object")
    normalized = {
        "agent_spawns": metric_value(metrics, "agent_spawns", "agents_spawned"),
        "model_calls": metric_value(metrics, "model_calls", "model_calls_used"),
        "rounds": metric_value(metrics, "rounds", "rounds_completed"),
        "output_kb": metric_value(metrics, "output_kb", "cumulative_output_kb"),
        "wall_seconds": metric_value(metrics, "wall_seconds", "elapsed_seconds", "duration_seconds"),
    }
    for field in ("agent_spawns", "model_calls", "rounds"):
        value = normalized[field]
        if isinstance(value, bool) or not isinstance(value, int):
            raise BudgetError(f"metrics.{field} must be an integer")
        if value < 0:
            raise BudgetError(f"metrics.{field} must be >= 0")
    for field in ("output_kb", "wall_seconds"):
        value = normalized[field]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise BudgetError(f"metrics.{field} must be numeric")
        if value < 0:
            raise BudgetError(f"metrics.{field} must be >= 0")
    return normalized


def ratios_and_remaining(policy, metrics):
    limits = policy["limits"]
    checks = {
        "agent_spawns": ("max_agent_spawns", metrics["agent_spawns"]),
        "model_calls": ("max_model_calls", metrics["model_calls"]),
        "rounds": ("max_rounds", metrics["rounds"]),
        "output_kb": ("max_output_kb", metrics["output_kb"]),
        "wall_seconds": ("max_wall_seconds", metrics["wall_seconds"]),
    }
    ratios = {}
    remaining = {}
    for metric_name, (limit_name, used) in checks.items():
        limit = limits[limit_name]
        ratios[metric_name] = 1.0 if limit == 0 and used > 0 else (used / limit if limit else 0.0)
        remaining[metric_name] = max(0, limit - used)
    finalization_remaining = limits["max_model_calls"] - metrics["model_calls"] - limits["reserved_finalization_calls"]
    remaining["model_calls_after_finalization_reserve"] = max(0, finalization_remaining)
    return ratios, remaining


def level_for_ratios(ratios):
    max_ratio = max(ratios.values()) if ratios else 0.0
    for level, threshold, action in THRESHOLDS:
        if max_ratio >= threshold:
            return level, action, max_ratio
    return "none", "logged", max_ratio


def evaluate_policy(policy, metrics):
    normalized = normalize_metrics(metrics)
    ratios, remaining = ratios_and_remaining(policy, normalized)
    level, action, max_ratio = level_for_ratios(ratios)
    return {
        "allowed": True,
        "level": level,
        "action": action,
        "max_ratio": round(max_ratio, 4),
        "ratios": {key: round(value, 4) for key, value in ratios.items()},
        "remaining": remaining,
    }


def apply_additions(metrics, args):
    updated = dict(metrics)
    updated["agent_spawns"] += args.add_agent_spawns
    updated["model_calls"] += args.add_model_calls
    updated["rounds"] += args.add_rounds
    return updated


def check_policy(policy, metrics, args):
    for field, value in (
        ("add-agent-spawns", args.add_agent_spawns),
        ("add-model-calls", args.add_model_calls),
        ("add-rounds", args.add_rounds),
    ):
        validate_int(value, field)

    current = normalize_metrics(metrics)
    proposed = apply_additions(current, args)
    result = evaluate_policy(policy, proposed)
    violations = []
    limits = policy["limits"]

    hard_checks = {
        "agent_spawns": "max_agent_spawns",
        "model_calls": "max_model_calls",
        "rounds": "max_rounds",
        "output_kb": "max_output_kb",
        "wall_seconds": "max_wall_seconds",
    }
    for metric_name, limit_name in hard_checks.items():
        if proposed[metric_name] > limits[limit_name]:
            violations.append(f"{metric_name} would exceed {limit_name}")

    if args.phase and not phase_enabled(policy, args.phase):
        violations.append(f"optional phase disabled by policy: {args.phase}")

    reserved_available = limits["max_model_calls"] - proposed["model_calls"]
    consumes_reserve = args.phase in FINALIZATION_PHASES
    if not consumes_reserve and reserved_available < limits["reserved_finalization_calls"]:
        violations.append("reserved finalization model-call budget would be crossed")

    result["proposed_metrics"] = proposed
    if violations:
        result["allowed"] = False
        result["action"] = "block"
        result["violations"] = violations
    return result


def add_policy_file_arg(parser):
    parser.add_argument("--policies", default=None, help="Path to budget-policies.json")


def command_defaults(args):
    catalog = load_catalog(args.policies)
    emit(get_policy(catalog, args.skill, args.tier))


def command_estimate(args):
    catalog = load_catalog(args.policies)
    policy = get_policy(catalog, args.skill, args.tier)
    emit(estimate_policy(policy, args.core, args.specialists, args.rounds))


def command_evaluate(args):
    policy = load_json(args.policy_file, "policy file")
    validate_policy(policy)
    metrics = load_json(args.metrics_file, "metrics file")
    emit(evaluate_policy(policy, metrics))


def command_check(args):
    policy = load_json(args.policy_file, "policy file")
    validate_policy(policy)
    metrics = load_json(args.metrics_file, "metrics file")
    result = check_policy(policy, metrics, args)
    emit(result)
    if not result["allowed"]:
        raise SystemExit(2)


def build_parser():
    parser = argparse.ArgumentParser(description="Spectra budget policy tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    defaults = subparsers.add_parser("defaults", help="Print default policy for a skill/tier")
    add_policy_file_arg(defaults)
    defaults.add_argument("skill")
    defaults.add_argument("tier")
    defaults.set_defaults(func=command_defaults)

    estimate = subparsers.add_parser("estimate", help="Print a dry-run estimate for a skill/tier")
    add_policy_file_arg(estimate)
    estimate.add_argument("skill")
    estimate.add_argument("tier")
    estimate.add_argument("core", nargs="?", type=int)
    estimate.add_argument("specialists", nargs="?", type=int)
    estimate.add_argument("rounds", nargs="?", type=int)
    estimate.set_defaults(func=command_estimate)

    evaluate = subparsers.add_parser("evaluate", help="Evaluate metrics against a policy")
    evaluate.add_argument("policy_file")
    evaluate.add_argument("metrics_file")
    evaluate.set_defaults(func=command_evaluate)

    check = subparsers.add_parser("check", help="Check whether proposed usage is allowed")
    check.add_argument("policy_file")
    check.add_argument("metrics_file")
    check.add_argument("--add-agent-spawns", type=int, default=0)
    check.add_argument("--add-model-calls", type=int, default=0)
    check.add_argument("--add-rounds", type=int, default=0)
    check.add_argument("--phase", default=None)
    check.set_defaults(func=command_check)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if hasattr(args, "policies") and args.policies is None:
        args.policies = str(Path(__file__).resolve().parent.parent / "schemas" / "budget-policies.json")
    try:
        args.func(args)
    except BudgetError as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
