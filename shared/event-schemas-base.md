# Event Schemas — Shared Base

This file defines the common JSONL event types used by all skills. Domain-specific event types are defined in each skill's own `event-schemas.md`.

## Event Metadata (Required on ALL Events)

Every event MUST include these fields:

| Field | Type | Description |
|---|---|---|
| `event_id` | UUID v4 | Unique identifier for deduplication and cross-referencing |
| `sequence_number` | Integer | Monotonically increasing, starting at 1. No gaps allowed. |
| `schema_version` | String | Semver (currently `"1.0.0"`) for forward compatibility |
| `session_id` | String | Links event to the session (matches `session_start.session_id`) |
| `timestamp` | String | ISO 8601 UTC with millisecond precision (e.g., `"2026-02-28T17:01:00.000Z"`) |

Response events SHOULD include `parent_event_id` referencing the event they respond to. Full causality tracking deferred to v2.

## Common Event Types

### `session_start`

First event in every session. Exactly one per file.

```json
{
  "event_id": "uuid",
  "sequence_number": 1,
  "schema_version": "1.0.0",
  "type": "session_start",
  "timestamp": "ISO-8601",
  "session_id": "{skill}-{topic}-{timestamp}",
  "agents": ["agent-1", "agent-2", "..."],
  "tier": "quick | standard | deep"
}
```

Additional skill-specific fields are added by each skill (e.g., `document` and `document_type` for deep-design, `decision_question` and `options` for decision-board).

### `phase_transition`

Records state machine transitions between session phases.

```json
{
  "event_id": "uuid",
  "sequence_number": 4,
  "schema_version": "1.0.0",
  "type": "phase_transition",
  "timestamp": "ISO-8601",
  "from": "PHASE_A",
  "to": "PHASE_B",
  "trigger": "trigger_reason"
}
```

Valid phases and triggers are skill-specific.

### `agent_complete`

An agent has finished a phase (completed, timed out, or errored).

```json
{
  "event_id": "uuid",
  "sequence_number": 11,
  "schema_version": "1.0.0",
  "type": "agent_complete",
  "timestamp": "ISO-8601",
  "agent": "agent-name",
  "phase": "opening | discussion | final_positions",
  "status": "completed | timeout | error"
}
```

### `session_complete`

Sentinel event written by the moderator after all data collection phases are done and the synthesis brief is produced, before synthesis begins. Synthesis agents MUST verify this event exists before processing.

```json
{
  "event_id": "uuid",
  "sequence_number": 15,
  "schema_version": "1.0.0",
  "type": "session_complete",
  "timestamp": "ISO-8601",
  "final_sequence_number": 15
}
```

The `final_sequence_number` equals this event's own `sequence_number`. The moderator continues numbering from `final_sequence_number + 1` for post-synthesis events.

### `session_end`

Final summary event written by the moderator after synthesis agents complete.

```json
{
  "event_id": "uuid",
  "sequence_number": 16,
  "schema_version": "1.0.0",
  "type": "session_end",
  "timestamp": "ISO-8601",
  "quality": "Full | Partial | Minimal",
  "agent_count": 10
}
```

Additional skill-specific fields are added by each skill (e.g., `topics_total` for deep-design, `consensus_strength` for decision-board).

### `feedback`

Post-session user feedback, written by the moderator.

```json
{
  "event_id": "uuid",
  "sequence_number": 17,
  "schema_version": "1.0.0",
  "type": "feedback",
  "timestamp": "ISO-8601",
  "rating": "very_helpful | somewhat_helpful | not_helpful",
  "freeform": "Optional user text"
}
```

All fields except `event_id`, `sequence_number`, `schema_version`, `type`, and `timestamp` are nullable. Written after the `session_end` event. Additional skill-specific fields may be included.

### `security_violation`

Logged when the moderator's post-phase directory audit detects unexpected file activity within the session directory, or when agent output fails content sanitization. Part of the 3-layer security defense (see `~/.claude/skills/shared/security.md`).

```json
{
  "event_id": "uuid",
  "sequence_number": 18,
  "schema_version": "1.0.0",
  "type": "security_violation",
  "timestamp": "ISO-8601",
  "violation_type": "unexpected_file | content_injection | path_escape",
  "agent": "agent-name",
  "detail": "Description of the violation",
  "action_taken": "flagged | excluded | session_halted"
}
```

- `unexpected_file`: A file not on the phase allowlist was created/modified in the session directory
- `content_injection`: Agent output contained suspected prompt injection or instruction-following from the source material
- `path_escape`: A write attempt targeted a path outside the session directory
- `action_taken`: `flagged` (logged only), `excluded` (data excluded from synthesis), `session_halted` (session aborted)

### `composition_invoked`

Written by the parent skill's moderator when a composition is initiated. See `~/.claude/skills/shared/composition.md` for the full composition protocol.

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

| Field | Type | Description |
|---|---|---|
| `composition_id` | String | Unique identifier for this composition (`comp-{uuid}`) |
| `child_skill` | String | The skill being invoked as the child |
| `child_tier` | String | Tier the child will run at (one below parent) |
| `trigger_reason` | String | Human-readable reason for the composition |
| `request_file` | String | Filename of the composition request (always `composition-request.json`) |

### `composition_completed`

Written by the parent skill's moderator after the child skill finishes. Pairs with a prior `composition_invoked` event via `composition_id`.

```json
{
  "event_id": "uuid",
  "sequence_number": 13,
  "schema_version": "1.0.0",
  "type": "composition_completed",
  "timestamp": "ISO-8601",
  "composition_id": "comp-{uuid}",
  "child_session_id": "decision-board-mfa-scope-20260228T170100",
  "child_session_dir": "~/.claude/decision-board-sessions/mfa-scope-20260228T170100/",
  "child_quality": "Full",
  "outcome_summary": "Recommended: MFA for admin roles now, all users in v2. 85% consensus.",
  "parent_event_id": "uuid-of-composition_invoked"
}
```

| Field | Type | Description |
|---|---|---|
| `composition_id` | String | Matches the `composition_invoked` event |
| `child_session_id` | String | The child skill's session ID |
| `child_session_dir` | String | Path to the child's session directory |
| `child_quality` | String | Child session quality (`Full`, `Partial`, `Minimal`, or `Error`) |
| `outcome_summary` | String | Human-readable summary of the child's result |
| `parent_event_id` | String | `event_id` of the corresponding `composition_invoked` event |

## JSONL Write Semantics

- **Single writer**: The moderator writes ALL events throughout the entire session. No writer handoff.
- **Atomic writes**: Each event batch is serialized with `json.dumps()`, appended with `flush()` + `fsync()` for durability.
- **Sequence numbers**: Monotonically increasing `sequence_number` on every event. Gaps indicate data loss.
- **JSON serialization**: All events MUST use a proper JSON serializer (`python3 -c 'import json; ...'` or equivalent). Never use string concatenation or `echo` with interpolated values — this prevents injection via crafted agent output.
- **Session complete sentinel**: The moderator writes a `session_complete` event as the **last event before synthesis**. Synthesis agents verify this sentinel exists before producing output.

## Quality Computation

`session_end.quality` is computed deterministically. The base formula is:

| Quality | Condition |
|---|---|
| **Full** | All selected agents completed all phases AND all domain-specific completeness criteria met |
| **Partial** | At least `ceil(n/2)` agents completed AND minimum domain-specific criteria met |
| **Minimal** | Above quorum (2 agents) but below Partial thresholds |

Where `n` is the number of agents in `session_start.agents`. Domain-specific completeness criteria are defined in each skill's SKILL.md.
