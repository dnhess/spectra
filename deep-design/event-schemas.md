# Event Schemas — Deep Design Review

This file defines domain-specific event types for deep-design. For common event types (session_start, phase_transition, agent_complete, session_complete, session_end, feedback, security_violation), see `~/.claude/skills/shared/event-schemas-base.md`.

## Domain-Specific Event Types

### `review`

An agent's independent review from the opening round.

```json
{
  "event_id": "uuid",
  "sequence_number": 2,
  "schema_version": "1.0.0",
  "type": "review",
  "agent": "fe-engineer",
  "phase": "opening",
  "timestamp": "ISO-8601",
  "observations": [
    {
      "text": "Component tree is 6 levels deep",
      "severity": "critical | major | minor",
      "id": "obs-uuid"
    }
  ],
  "recommendations": ["Flatten with composition pattern"]
}
```

### `specialist_request`

System recommends a domain specialist based on opening round findings.

```json
{
  "event_id": "uuid",
  "sequence_number": 3,
  "schema_version": "1.0.0",
  "type": "specialist_request",
  "agent": "system",
  "specialist": "hipaa-compliance",
  "justification": "Document describes PHI handling"
}
```

### `specialist_recommended`

Records the outcome of a specialist recommendation — whether the user approved it and whether it was spawned. Enables `specialist_utilization` KPI tracking.

```json
{
  "event_id": "uuid",
  "sequence_number": 4,
  "schema_version": "1.1.0",
  "type": "specialist_recommended",
  "timestamp": "ISO-8601",
  "specialist": "hipaa-compliance",
  "justification": "Document describes PHI handling",
  "user_approved": true,
  "spawned": true
}
```

| Field | Type | Description |
|---|---|---|
| `specialist` | String | Name of the recommended specialist |
| `justification` | String | Why this specialist was recommended |
| `user_approved` | Boolean | Whether the user approved the recommendation |
| `spawned` | Boolean | Whether the specialist agent was actually spawned |

### `topic_created`

A discussion topic extracted from opening round disagreements.

```json
{
  "event_id": "uuid",
  "sequence_number": 5,
  "schema_version": "1.0.0",
  "type": "topic_created",
  "id": "T001",
  "title": "API pagination strategy",
  "raised_by": "be-engineer",
  "assigned_to": ["fe-engineer", "be-engineer"],
  "status": "open"
}
```

### `rebuttal`

An agent's response to a discussion topic.

```json
{
  "event_id": "uuid",
  "sequence_number": 6,
  "schema_version": "1.0.0",
  "type": "rebuttal",
  "agent": "fe-engineer",
  "topic": "T001",
  "position": "Cursor-based pagination better for infinite scroll UX",
  "round": 1,
  "parent_event_id": "uuid-of-topic"
}
```

### `pass`

An agent explicitly passes on a topic (nothing to add). Required for convergence detection.

```json
{
  "event_id": "uuid",
  "sequence_number": 7,
  "schema_version": "1.0.0",
  "type": "pass",
  "agent": "fe-engineer",
  "topic": "T001",
  "round": 1
}
```

### `topic_resolved`

A discussion topic has been resolved or deferred.

```json
{
  "event_id": "uuid",
  "sequence_number": 8,
  "schema_version": "1.0.0",
  "type": "topic_resolved",
  "id": "T001",
  "status": "resolved | deferred",
  "summary": "Cursor-based pagination with offset fallback for admin views",
  "round": 1,
  "resolved_by": "discussion | escalation | composition | deferred",
  "composition_id": null
}
```

Optional fields:

- `resolved_by`: How the topic was resolved. `discussion` (agents converged), `escalation` (user decided), `composition` (child skill resolved via composition protocol), `deferred` (postponed). Defaults to `discussion` for backward compatibility.
- `composition_id`: If `resolved_by` is `composition`, the `composition_id` linking to the `composition_invoked`/`composition_completed` events. `null` otherwise.

### `escalation`

A deadlocked topic escalated to the user for decision.

```json
{
  "event_id": "uuid",
  "sequence_number": 9,
  "schema_version": "1.0.0",
  "type": "escalation",
  "topic": "T002",
  "positions": {
    "security-expert": "Require MFA for all users",
    "pm": "MFA only for admin roles"
  },
  "status": "pending"
}
```

### `escalation_resolved`

User has resolved a deadlocked topic.

```json
{
  "event_id": "uuid",
  "sequence_number": 10,
  "schema_version": "1.0.0",
  "type": "escalation_resolved",
  "topic": "T002",
  "decision": "MFA for admin roles, optional for regular users",
  "decided_by": "user"
}
```

### `final_position`

An agent's top 3 recommendations at the end of discussion.

```json
{
  "event_id": "uuid",
  "sequence_number": 14,
  "schema_version": "1.0.0",
  "type": "final_position",
  "agent": "fe-engineer",
  "recommendations": [
    "Flatten component tree",
    "Add error boundaries at route level",
    "Use React.lazy for code splitting"
  ]
}
```

## Deep-Design `session_start` Extensions

The `session_start` event (defined in shared base) includes these additional fields for deep-design:

```json
{
  "document": "path/to/document",
  "stack": "Next.js + TypeScript",
  "document_type": "product_spec | technical_architecture | full_design"
}
```

## Deep-Design `session_end` Extensions

The `session_end` event (defined in shared base) includes these additional fields for deep-design:

```json
{
  "topics_total": 5,
  "topics_resolved": 4,
  "topics_escalated": 1,
  "compositions_invoked": 0,
  "topics_resolved_by_composition": 0,
  "quality_kpis": {
    "completion_rate": 0.857,
    "phase_completion_rate": 1.0,
    "security_violations_count": 0,
    "convergence_rate": 0.80,
    "specialist_utilization": 0.50,
    "escalations_count": 1
  }
}
```

- `compositions_invoked`: Number of skill compositions invoked during the session (0 or 1, max 1 per session).
- `topics_resolved_by_composition`: Number of topics resolved via composition (subset of `topics_resolved`).
- `quality_kpis`: Optional object (additive, schema 1.1.0) containing shared and domain-specific quality metrics. Shared KPIs are defined in `event-schemas-base.md`. Deep-design-specific KPI formulas:

| Metric | Formula | Data Source | Edge Cases |
|---|---|---|---|
| `convergence_rate` | `count(topic_resolved WHERE status IN (resolved, user_decided)) / count(topic_created)` | Event log | 0 topics = null |
| `specialist_utilization` | `count(specialist_recommended WHERE spawned=true) / count(specialist_recommended)` | Event log | 0 recommended = null |
| `escalations_count` | `count(escalation)` | Event log | 0 is healthy |

## JSONL Write Semantics

- **Single writer**: The moderator writes ALL events throughout the entire session. No writer handoff.
- **Atomic writes**: Each event batch is serialized with `json.dumps()`, appended with `flush()` + `fsync()` for durability.
- **Sequence numbers**: Monotonically increasing `sequence_number` on every event. Gaps indicate data loss.
- **JSON serialization**: All events MUST use a proper JSON serializer (e.g., `python3 -c 'import json; ...'`). Never use string concatenation or `echo` with interpolated values — this prevents injection via crafted agent review text.
- **Session complete sentinel**: The moderator writes a `session_complete` event as the **last event before synthesis**. The synthesis agent verifies this sentinel exists before producing output.

## Quality Computation

`session_end.quality` is computed deterministically:

| Quality | Condition |
|---|---|
| **Full** | All selected agents completed their reviews AND all topics resolved or deferred |
| **Partial** | At least `ceil(n/2)` agents completed AND at least 1 topic resolved |
| **Minimal** | Above quorum (2 agents) but below Partial thresholds |

Where `n` is the number of agents in `session_start.agents`.

## Cross-Session Manifest Schema

Each entry in `~/.spectra/sessions/deep-design/manifest.jsonl` includes all common manifest fields (defined in `~/.claude/skills/shared/event-schemas-base.md`) plus these domain-specific fields:

```json
{
  "document": "path/to/document",
  "document_type": "product_spec | technical_architecture | full_design",
  "topics_total": 4,
  "topics_resolved": 3,
  "topics_escalated": 1,
  "topics_deferred": 0,
  "agents_timed_out": 0,
  "findings_critical": 3,
  "findings_major": 7,
  "findings_minor": 2,
  "feedback": null,
  "compositions_invoked": 0,
  "composition_ids": []
}
```

- `feedback`: Nullable freeform feedback text (populated after user provides post-review feedback).
- `compositions_invoked`: Number of skill compositions invoked during the session (0 or 1).
- `composition_ids`: Array of `composition_id` strings from any `composition_invoked` events. Empty array if no compositions.
