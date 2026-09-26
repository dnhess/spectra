# Local Budget Calibration Trials

This procedure collects trustworthy local evidence before changing Spectra's default session
budgets. It measures observable proxies only: agent spawns, model calls, completed rounds, output
size, and elapsed time. It does not estimate tokens or dollars.

## 1. Prepare the Development Install

From the Spectra repository:

```bash
npm install
spectra link .
spectra doctor
```

Confirm that `spectra status` lists all five session-producing skills and that `spectra budget`
opens successfully.

## 2. Choose One Calibration Bucket

Start with one skill and tier, such as `peer-review/standard`. Quick, Standard, and Deep runs are
separate buckets; do not mix them. Use a representative mix of small, typical, and difficult tasks
that genuinely belong in the chosen tier.

Complete at least 20 Full-quality sessions across at least seven days. More than 50 runs across 14
days produces high-confidence evidence. Do not manufacture repeated trivial tasks merely to reach
the threshold.

For the first real Standard-tier trial, review Spectra's current working changes with a provider-side
spend ceiling:

```bash
claude --model sonnet --effort medium --max-budget-usd 5 --permission-mode auto -p \
  "Use the peer-review skill at Standard tier to review the current uncommitted changes. \
This is calibration trial 1. Show and obey the budget preflight, do not modify repository files, \
and finalize the session telemetry even if the review is partial."
```

Run this from the repository being reviewed. The provider-side ceiling is an additional emergency
stop; Spectra's proxy budget remains the orchestration control. If the ceiling interrupts the run,
retain it as interrupted evidence but do not use it for calibration recommendations.

## 3. Verify Telemetry After Each Run

```bash
spectra budget --skill peer-review --limit 5
spectra budget --skill peer-review --limit 5 --json
```

For a completed run, verify:

- `state` is `complete` and `quality` is `Full`
- policy and metrics compatibility fields are valid
- `observed` counters are non-zero where work occurred
- finalization reserve `usage_known` is true for newly measured sessions
- `budget-summary.json` has summary version 1.1.0 and a policy fingerprint

Interrupted, Partial, Minimal, legacy, malformed, caveated, or live-derived sessions remain visible
in ordinary reports but are excluded from recommendations.

## 4. Review Recommendations

```bash
spectra budget calibrate --skill peer-review --tier standard
spectra budget calibrate --skill peer-review --tier standard --json
```

Before the evidence gate, the result should be `insufficient_evidence`. After the gate, review every
suggested reduction against the recorded task mix. The tool preserves the largest successful run
plus 15% headroom and the default-plan floor. It cannot raise limits or change agent rosters,
finalization reserves, optional phases, or model routing.

The command never modifies `shared/schemas/budget-policies.json`. Any accepted change should be a
normal reviewed repository edit with policy tests and the full test suite.

## 5. Regression Trial

After manually accepting a policy reduction:

1. Run the policy test suite.
2. Repeat at least three representative tasks from the bucket, including the previous largest case.
3. Confirm required finalization and verification still complete.
4. Revert the reduction if completion quality falls or valid work is blocked.
5. Record the evidence and decision in the changelog or pull request.

Synthetic fixtures in `test/budget_metrics.bats` and `test/budget_calibration.bats` exercise the
telemetry and recommendation contracts. They validate mechanics but do not replace real-session
evidence.
