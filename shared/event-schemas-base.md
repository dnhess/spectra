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

## Schema Versioning

Event schemas follow [Semantic Versioning](https://semver.org/):

- **Current version**: `1.1.0`
- **Minor version bump** (e.g., 1.0.0 to 1.1.0): Additive changes only — new optional fields on existing event types, new event types. Readers MUST ignore unknown fields. Writers MUST NOT remove or rename existing fields.
- **Major version bump** (e.g., 1.x to 2.0.0): Breaking changes — removed fields, renamed fields, changed field types or semantics. Readers SHOULD reject events with an unrecognized major version rather than silently misinterpreting data.

### Compatibility Contract

- All events carry `schema_version` in their metadata (see above)
- Consumers reading events MUST tolerate unknown fields (forward compatibility)
- Consumers MAY reject events whose major version exceeds their known maximum
- The `schema_migrations` table in `~/.spectra/spectra.db` tracks which schema version the local installation expects (see `shared/tools/db-utils.sh`)

### Version History

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-02-28 | Initial schema — all base event types |
| 1.1.0 | 2026-03-01 | Added context_budget_status, emergency_checkpoint events; quality_kpis on session_end; interrupted quality value |

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

An agent has finished a phase (completed, timed out, errored, or failed validation).

```json
{
  "event_id": "uuid",
  "sequence_number": 11,
  "schema_version": "1.0.0",
  "type": "agent_complete",
  "timestamp": "ISO-8601",
  "agent": "agent-name",
  "phase": "opening | discussion | final_positions",
  "status": "completed | timeout | error | validation_failed | read_error"
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
  "quality": "Full | Partial | Minimal | interrupted",
  "agent_count": 10,
  "quality_kpis": {
    "completion_rate": 0.90,
    "phase_completion_rate": 1.0,
    "security_violations_count": 0
  }
}
```

Additional skill-specific fields are added by each skill (e.g., `topics_total` for deep-design, `consensus_strength` for decision-board).

The `quality_kpis` object is optional (additive, schema 1.1.0). Each skill extends this object with domain-specific KPIs. Shared KPI formulas:

| Metric | Formula | Data Source | Edge Cases |
|---|---|---|---|
| `completion_rate` | `count(agent_complete WHERE status=completed) / count(agent_complete)` | Event log | 0/0 = null |
| `phase_completion_rate` | `count(phase_transition) / phases_planned` | Event log + session config | Interrupted: use phases completed at interruption |
| `security_violations_count` | `count(security_violation)` | Event log | 0 is expected |

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
  "child_session_dir": "~/.spectra/sessions/decision-board/mfa-scope-20260228T170100/",
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

### `checkpoint_written`

Records that a state checkpoint was written at a phase transition. See `shared/orchestration.md` for the checkpoint protocol.

```json
{
  "event_id": "uuid",
  "session_id": "session-id",
  "sequence_number": 8,
  "schema_version": "1.0.0",
  "type": "checkpoint_written",
  "timestamp": "ISO-8601",
  "phase": "discussion_round_1",
  "checkpoint_file": "session-state.md"
}
```

| Field | Type | Description |
|---|---|---|
| `phase` | String | The phase that just completed |
| `checkpoint_file` | String | Filename of the checkpoint (always `session-state.md`) |

### `handoff_written`

Records that a session handoff file was generated. Counts are derived from `synthesis-brief.json` fields, not from parsing handoff markdown.

```json
{
  "event_id": "uuid",
  "session_id": "session-id",
  "sequence_number": 19,
  "schema_version": "1.0.0",
  "type": "handoff_written",
  "timestamp": "ISO-8601",
  "handoff_file": "handoff.md",
  "unresolved_items": 1,
  "followup_recommendations": 4
}
```

| Field | Type | Description |
|---|---|---|
| `handoff_file` | String | Filename of the handoff (always `handoff.md`) |
| `unresolved_items` | Integer | Count of unresolved/deferred items from `synthesis-brief.json` |
| `followup_recommendations` | Integer | Count of follow-up recommendations |

### `context_budget_status`

Emitted at every phase transition to track proxy metrics for context window pressure. Part of the measurement-only context budget monitoring system (see `shared/orchestration.md` > Context Budget Monitoring).

```json
{
  "event_id": "uuid",
  "session_id": "session-id",
  "sequence_number": 9,
  "schema_version": "1.1.0",
  "type": "context_budget_status",
  "timestamp": "ISO-8601",
  "phase": "discussion_round_3",
  "metrics": {
    "rounds_completed": 3,
    "cumulative_output_kb": 127.4,
    "agents_spawned": 15,
    "moderator_output_kb": 42.1
  },
  "active_threshold": "none | warning | caution | critical",
  "tier_limits": { "max_rounds": 5, "max_output_kb": 300 },
  "action_taken": "logged | checkpoint_written | reduce_agents | force_final"
}
```

| Field | Type | Description |
|---|---|---|
| `phase` | String | Current phase when status was computed |
| `metrics.rounds_completed` | Integer | Number of discussion/debate rounds completed so far |
| `metrics.cumulative_output_kb` | Float | Total size of all agent output JSON files read by moderator (KB) |
| `metrics.agents_spawned` | Integer | Total number of agents spawned across all phases |
| `metrics.moderator_output_kb` | Float | Estimated size of moderator's own output (event log + checkpoints) in KB |
| `active_threshold` | String | Current threshold level: `none`, `warning`, `caution`, or `critical` |
| `tier_limits` | Object | The tier-specific limits being measured against |
| `action_taken` | String | Action taken at this threshold level (measurement-only for first 20 sessions) |

### `emergency_checkpoint`

Written when context pressure reaches critical levels or compaction is detected. Contains structured recovery state enabling session resumption after restart.

```json
{
  "event_id": "uuid",
  "session_id": "session-id",
  "sequence_number": 42,
  "schema_version": "1.1.0",
  "type": "emergency_checkpoint",
  "timestamp": "ISO-8601",
  "phase": "discussion",
  "sub_step": "polling_round_3",
  "recovery_state": {
    "resume_phase": "discussion",
    "resume_round": 3,
    "resume_step": "polling",
    "completed_agents": [
      { "agent_id": "arch", "output_path": "discussion/round-3/arch.json", "processing_status": "consumed" }
    ],
    "pending_agents": [
      { "agent_id": "perf", "expected_output_path": "discussion/round-3/perf.json", "assigned_topics": ["T001"] }
    ],
    "event_log_sequence_number": 42,
    "session_config": {
      "tier": "deep",
      "agent_roster": ["arch", "sec", "perf"],
      "phase_plan": ["opening", "discussion", "final_positions", "synthesis"]
    },
    "checkpoint_reason": "context_budget_critical | compaction_detected",
    "context_budget_at_checkpoint": {
      "rounds_completed": 3,
      "cumulative_output_kb": 287.5,
      "agents_spawned": 18
    },
    "security_violations_active": false
  },
  "recovery_context": "Human-readable context string for supplementary information"
}
```

| Field | Type | Description |
|---|---|---|
| `phase` | String | Phase active when emergency was triggered |
| `sub_step` | String | Specific sub-step within the phase |
| `recovery_state.resume_phase` | String | Phase to resume from |
| `recovery_state.resume_round` | Integer | Round number to resume from (if applicable) |
| `recovery_state.resume_step` | String | Step within the phase to resume from |
| `recovery_state.completed_agents` | Array | Agents whose output has been consumed |
| `recovery_state.pending_agents` | Array | Agents that were in-flight or expected |
| `recovery_state.event_log_sequence_number` | Integer | Last sequence number written to event log |
| `recovery_state.session_config` | Object | Session configuration for reconstruction |
| `recovery_state.checkpoint_reason` | String | Why the emergency checkpoint was triggered |
| `recovery_state.context_budget_at_checkpoint` | Object | Budget metrics at time of checkpoint |
| `recovery_state.security_violations_active` | Boolean | Whether any security violations were active |
| `recovery_context` | String | Human-readable supplementary context |

## Cross-Session Manifest Base Schema

Every manifest entry MUST include these common fields. Domain-specific fields are defined in each skill's `event-schemas.md`.

```json
{
  "session_id": "{skill}-{topic}-{timestamp}",
  "timestamp": "ISO-8601",
  "project": "basename of working directory at invocation time",
  "tier": "quick | standard | deep",
  "agent_count": 7,
  "specialist_count": 1,
  "quality": "Full | Partial | Minimal",
  "duration_seconds": 480,
  "feedback_rating": "very_helpful | somewhat_helpful | not_helpful | null",
  "has_handoff": false,
  "session_dirname": null
}
```

| Field | Type | Description |
|---|---|---|
| `session_id` | String | Session identifier, matches `session_start.session_id` |
| `timestamp` | String | ISO 8601 UTC timestamp of session completion |
| `project` | String | Basename of the working directory at invocation time (e.g., `my-app`). Enables per-project filtering of session history |
| `tier` | String | Session tier (`quick`, `standard`, or `deep`) |
| `agent_count` | Integer | Number of agents used |
| `specialist_count` | Integer | Number of specialist agents used |
| `quality` | String | Session quality (`Full`, `Partial`, or `Minimal`) |
| `duration_seconds` | Integer or null | Wall-clock duration of the session |
| `feedback_rating` | String or null | Post-session user rating. Nullable (populated after user provides feedback) |
| `has_handoff` | Boolean | Whether `handoff.md` was written for this session. Default `false` for pre-existing entries missing this field |
| `session_dirname` | String or null | Leaf directory name of the session directory. Resolved at read time via `~/.spectra/sessions/{skill}/{session_dirname}`. `null` for pre-existing entries |

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
| **interrupted** | Emergency shutdown — session halted by context pressure, checkpoint enables recovery |

Where `n` is the number of agents in `session_start.agents`. Domain-specific completeness criteria are defined in each skill's SKILL.md.
