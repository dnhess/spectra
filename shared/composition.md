# Skill Composition Protocol

This document defines the protocol for one skill to invoke another skill mid-session. Composition enables structured delegation — when a parent skill encounters a problem that another skill is purpose-built to solve, it can hand off to that child skill and resume with the results.

## Design Principles

- **Sequential, not concurrent**: Parent tears down its team before child runs. No concurrent teams.
- **User-gated**: Composition never auto-fires. The user always approves before a child skill is invoked.
- **Standard contracts**: `composition-request.json` is the input contract; the child's `synthesis-brief.json` is the output contract. No special response format needed.
- **Fault-tolerant**: All composition failures fall back to user escalation. Composition failures are never session-fatal.
- **Bounded**: Maximum 1 composition per session to bound cost and complexity.
- **Tier downgrade**: Child runs one tier below parent (Deep → Standard, Standard → Quick). Quick tier cannot compose.

## Composition Request Schema

The parent writes `composition-request.json` to its session directory before invoking the child skill.

```json
{
  "composition_id": "comp-{uuid}",
  "protocol_version": "1.0.0",
  "parent": {
    "skill": "deep-design",
    "session_id": "deep-design-{topic}-{timestamp}",
    "session_dir": "~/.spectra/sessions/deep-design/{topic}-{timestamp}/",
    "current_phase": "discussion",
    "trigger_reason": "deadlock on T002 — MFA scope"
  },
  "child": {
    "skill": "decision-board",
    "tier_override": "standard",
    "skip_confirmation": true,
    "skip_feedback": true,
    "invocation_type": null
  },
  "request": {
    "question": "Should MFA be required for all users or only admin roles?",
    "options": [
      "MFA for all users",
      "MFA for admin roles only",
      "MFA for admin roles now, all users in v2"
    ],
    "constraints": [
      "Must not block MVP launch",
      "Must satisfy SOC 2 audit requirements"
    ],
    "context_summary": "Design review deadlocked on MFA scope. Security expert advocates universal MFA citing SOC 2. PM argues admin-only to reduce onboarding friction.",
    "positions": {
      "security-expert": "Require MFA for all users — SOC 2 mandates it",
      "pm": "MFA only for admin roles — user onboarding friction is the top churn driver"
    },
    "source_file_paths": ["path/to/design-doc.md"]
  }
}
```

### Field Reference

| Field | Type | Required | Description |
|---|---|---|---|
| `composition_id` | String | Yes | Unique identifier for this composition (`comp-{uuid}`) |
| `protocol_version` | String | Yes | Semver protocol version (currently `"1.0.0"`) |
| `parent.skill` | String | Yes | Parent skill name |
| `parent.session_id` | String | Yes | Parent's active session ID |
| `parent.session_dir` | String | Yes | Absolute path to parent's session directory |
| `parent.current_phase` | String | Yes | Phase the parent was in when composition triggered |
| `parent.trigger_reason` | String | Yes | Human-readable reason for composition |
| `child.skill` | String | Yes | Child skill to invoke |
| `child.tier_override` | String | Yes | Tier for child session (one below parent) |
| `child.skip_confirmation` | Boolean | Yes | Skip the child skill's confirmation gate |
| `child.skip_feedback` | Boolean | Yes | Skip the child skill's post-session feedback survey |
| `child.invocation_type` | String | No | Optional invocation type hint for the child skill. Use `"verification_hook"` when the child skill should operate in headless hook mode rather than its standard interactive flow. Defaults to `null`. |
| `request.question` | String | Yes | The question for the child skill to resolve |
| `request.options` | Array | No | Pre-defined options (child skill may generate its own if omitted) |
| `request.constraints` | Array | No | Hard constraints the answer must satisfy |
| `request.context_summary` | String | Yes | Summary of the parent's context relevant to this question |
| `request.positions` | Object | No | Named positions from the parent session (agent → position) |
| `request.source_file_paths` | Array | No | File paths the child skill should read for context |

## 7-Step Composition Lifecycle

### Step 1: Parent Detects Need

The parent skill identifies a situation where another skill would produce a better outcome than continuing within its own framework. Detection criteria are skill-specific (e.g., deep-design detects a deadlocked discussion topic).

**Eligibility check** (parent verifies before proceeding):

- Current tier is Standard or Deep (Quick cannot compose)
- No prior composition in this session (`compositions_invoked == 0`)
- Child skill is installed (persona directory exists at `~/.claude/skills/{child_skill}/`)

If any check fails, the parent falls back to its normal escalation flow.

### Step 2: User Approval Gate

The parent presents the composition opportunity to the user. Composition never auto-fires.

```
--- Escalation: T002 — {title} ---

{Agent 1}: "{position}"
{Agent 2}: "{position}"

What should we do?
[1] {option 1}
[2] {option 2}
[3] Defer to v2
[d] Deliberate with decision-board (runs a structured debate)
[s] Skip — let agents continue discussing
[f] Free-form — type your own resolution
```

If the user selects `[d]`, composition proceeds. Any other selection follows the parent's normal resolution flow.

### Step 3: Write Request + Event

The parent:

1. Writes `composition-request.json` to its session directory
2. Writes a `composition_invoked` event to its JSONL event log (see Event Schemas below)

### Step 4: Parent TeamDelete

The parent tears down its team using `TeamDelete`. This is required because only one team can be active at a time. The parent's session directory, event log, and all files are preserved — only the team (live agents) is removed.

**Safety invariant**: Composition only triggers at user-facing gates (e.g., the escalation prompt), which occur *between* phases — never mid-phase. By the time the user sees the composition option, all agents from the current phase have completed, their output files are persisted on disk, and the team is idle. No agent work is lost by the TeamDelete.

### Step 5: Child Skill Executes

The moderator invokes the child skill as a full independent session:

1. The parent SKILL.md context is swapped out for the child SKILL.md
2. The child reads `composition-request.json` from the parent's session directory to bootstrap its input
3. The child runs its complete lifecycle (team setup → phases → synthesis → cleanup)
4. The child produces its standard output artifacts, including `synthesis-brief.json`

**Context handoff rules:**

- The child reads ONLY `composition-request.json` from the parent — never the parent's event log, agent files, or synthesis brief
- The parent reads ONLY `synthesis-brief.json` from the child — never the child's event log or agent files
- Each skill's JSONL event log is completely independent

### Step 6: Parent Reads Child Results

After the child completes, the moderator:

1. Reads the child's `synthesis-brief.json` from the child's session directory
2. Extracts the relevant resolution (recommendation, consensus strength, conditions, ADR path)
3. Writes a `composition_completed` event to the parent's JSONL event log

### Step 7: Parent Resumes

The parent resumes its session:

1. Re-creates its team for any remaining phases (e.g., final positions, synthesis)
2. Incorporates the child's resolution into the parent's context (e.g., resolves the deadlocked topic)
3. Continues from where it left off

**Resume state**: The parent uses its session directory (preserved throughout) and JSONL event log to reconstruct state. The `composition_completed` event provides the child's resolution.

## Event Schemas

These events are defined in `shared/event-schemas-base.md` and written by the parent moderator.

### `composition_invoked`

Written by the parent when composition begins (Step 3).

```json
{
  "event_id": "uuid",
  "sequence_number": 12,
  "schema_version": "1.0.0",
  "type": "composition_invoked",
  "timestamp": "ISO-8601",
  "composition_id": "comp-{uuid}",
  "child_skill": "decision-board",
  "child_tier": "standard",
  "trigger_reason": "deadlock on T002 — MFA scope",
  "request_file": "composition-request.json"
}
```

### `composition_completed`

Written by the parent after the child finishes (Step 6).

```json
{
  "event_id": "uuid",
  "sequence_number": 13,
  "schema_version": "1.0.0",
  "type": "composition_completed",
  "timestamp": "ISO-8601",
  "composition_id": "comp-{uuid}",
  "child_session_id": "decision-board-mfa-scope-20260228T170100",
  "child_session_dir": "~/.spectra/sessions/decision-board/mfa-scope-20260228T170100/",
  "child_quality": "Full",
  "outcome_summary": "Recommended: MFA for admin roles now, all users in v2. 85% consensus.",
  "parent_event_id": "uuid-of-composition_invoked"
}
```

## Tier Downgrade Matrix

| Parent Tier | Child Tier | Rationale |
|---|---|---|
| Deep | Standard | Child gets meaningful debate (1-2 rounds) without Deep cost |
| Standard | Quick | Child gets a sanity check — fast resolution for a scoped question |
| Quick | — | Quick tier cannot compose (not eligible) |

## Error Handling

All composition errors are recoverable. Composition failures never halt the parent session.

| Error | Detection | Recovery |
|---|---|---|
| Child skill not installed | Persona directory missing at `~/.claude/skills/{child_skill}/` | Fall back to user escalation |
| Child session fails | Child `session_end.quality` is `Minimal` or child errors out | Log warning, present partial results if available, fall back to user escalation |
| Child produces no synthesis-brief | `synthesis-brief.json` missing after child completes | Fall back to user escalation |
| Composition already used | `compositions_invoked >= 1` | Option not offered (eligibility check fails) |

On any error, the parent:

1. Writes a `composition_completed` event with `child_quality: "Error"` and `outcome_summary` describing the failure
2. Re-creates its team and resumes with the topic still unresolved
3. Falls back to the normal escalation flow (user decides)

## File-Write Allowlist

The `composition-request.json` file is added to the parent skill's file-write allowlist. It is written to the parent's session directory by the moderator (not by agents).

## Constraints

- **1 composition per session**: Prevents unbounded cost escalation and recursive composition chains
- **No recursive composition**: A child skill invoked via composition cannot itself compose (enforced by the 1-per-session limit and the tier downgrade — Quick tier is not eligible)
- **No concurrent teams**: Parent's `TeamDelete` must complete before child's `TeamCreate`
- **No cross-reading**: Parent and child never read each other's event logs or agent files. Only `composition-request.json` (parent → child) and `synthesis-brief.json` (child → parent) cross the boundary
