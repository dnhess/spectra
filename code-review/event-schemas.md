# Event Schemas — Code Review Board

This file defines domain-specific event types for code-review. For common event types (session_start, phase_transition, agent_complete, session_complete, session_end, feedback, security_violation, composition_invoked, composition_completed, checkpoint_written, handoff_written), see `~/.claude/skills/shared/event-schemas-base.md`.

## Domain-Specific Event Types

### `recon_complete`

The recon agent has finished analyzing the review target's structure, technologies, and test coverage.

```json
{
  "event_id": "uuid",
  "sequence_number": 2,
  "schema_version": "1.0.0",
  "type": "recon_complete",
  "timestamp": "ISO-8601",
  "agent": "recon",
  "phase": "recon",
  "technologies_detected": ["typescript", "express", "prisma"],
  "files_mapped": [
    {
      "path": "src/auth/service.ts",
      "lines": 342,
      "complexity": "high"
    },
    {
      "path": "src/auth/middleware.ts",
      "lines": 87,
      "complexity": "low"
    }
  ],
  "test_coverage_summary": {
    "has_tests": true,
    "test_files": ["src/auth/__tests__/service.test.ts"],
    "estimated_coverage": "partial"
  }
}
```

- `technologies_detected` (array of strings): Languages, frameworks, and libraries identified in the review target.
- `files_mapped` (array of objects): Files in scope with line count and complexity assessment (`high`, `medium`, `low`).
- `test_coverage_summary` (object): Whether tests exist, which test files were found, and estimated coverage level (`full`, `partial`, `none`).

### `research_complete`

The research agent has finished investigating best practices, known advisories, and deprecations for the detected technology stack.

```json
{
  "event_id": "uuid",
  "sequence_number": 3,
  "schema_version": "1.0.0",
  "type": "research_complete",
  "timestamp": "ISO-8601",
  "agent": "researcher",
  "phase": "recon",
  "technologies_researched": ["express@4.18", "prisma@5.x"],
  "advisories_found": [
    {
      "technology": "express",
      "advisory": "CVE-2024-XXXX: path traversal in static middleware",
      "severity": "major",
      "relevance": "high"
    }
  ],
  "deprecations_found": [
    {
      "technology": "prisma",
      "item": "findMany without select/include deprecated in favor of explicit field selection",
      "relevance": "medium"
    }
  ]
}
```

- `technologies_researched` (array of strings): Technologies investigated, with version where available.
- `advisories_found` (array of objects): Security advisories or known issues relevant to the codebase.
- `deprecations_found` (array of objects): Deprecated APIs or patterns detected in the technology stack.

### `finding`

A code review finding raised by a reviewer agent during the opening phase. Each finding identifies a specific issue with location, severity, and recommendation.

```json
{
  "event_id": "uuid",
  "sequence_number": 5,
  "schema_version": "1.0.0",
  "type": "finding",
  "timestamp": "ISO-8601",
  "agent": "security-reviewer",
  "phase": "opening",
  "id": "finding-uuid4",
  "severity": "critical",
  "category": "security",
  "file_path": "src/auth/service.ts",
  "line_range": [42, 58],
  "description": "SQL query constructed via string interpolation with unsanitized user input. Vulnerable to SQL injection.",
  "recommendation": "Use parameterized queries via Prisma's built-in query builder instead of raw SQL.",
  "confidence": "high",
  "references": [
    "OWASP SQL Injection Prevention Cheat Sheet",
    "Prisma docs: Raw database access"
  ]
}
```

- `id` (string): Unique finding identifier in `finding-{uuid4}` format. Used for cross-referencing in challenge, upheld, withdrawn, modified, and merged events.
- `severity` (enum): `critical` > `major` > `minor` > `nit`. Severity levels in descending order of importance.
- `category` (enum): One of `design`, `performance`, `security`, `reliability`, `testing`, `maintainability`.
- `file_path` (string): Path to the file containing the issue, relative to the review target root.
- `line_range` (array of two integers): Start and end line numbers (inclusive). May be `[n, n]` for single-line findings.
- `description` (string): What the issue is and why it matters.
- `recommendation` (string): Concrete suggestion for how to fix the issue.
- `confidence` (enum): `high`, `medium`, `low`. How confident the reviewer is that this is a genuine issue.
- `references` (array of strings): Supporting references — documentation, advisories, style guides, or prior art.

### `topic_created`

A discussion topic extracted from opening-round findings that require debate. Typically created when multiple reviewers disagree on severity, or when a finding is contested.

```json
{
  "event_id": "uuid",
  "sequence_number": 8,
  "schema_version": "1.0.0",
  "type": "topic_created",
  "timestamp": "ISO-8601",
  "id": "T001",
  "title": "SQL injection severity in auth service",
  "finding_ids": ["finding-uuid4-a", "finding-uuid4-b"],
  "raised_by": "security-reviewer",
  "assigned_to": ["security-reviewer", "reliability-reviewer"],
  "status": "open"
}
```

- `id` (string): Topic identifier in `T{NNN}` format.
- `title` (string): Human-readable summary of the discussion topic.
- `finding_ids` (array of strings): Finding IDs that triggered this topic.
- `raised_by` (string): The agent or system that created the topic.
- `assigned_to` (array of strings): Agents expected to participate in the discussion.
- `status` (enum): Always `open` at creation.

### `finding_challenged`

A reviewer challenges an existing finding during the discussion phase, arguing it is a false positive, overstated, or missing context.

```json
{
  "event_id": "uuid",
  "sequence_number": 9,
  "schema_version": "1.0.0",
  "type": "finding_challenged",
  "timestamp": "ISO-8601",
  "agent": "reliability-reviewer",
  "phase": "discussion",
  "finding_id": "finding-uuid4",
  "challenge_type": "overstated",
  "argument": "The raw SQL is only used in an admin-only migration script that runs offline. No user input reaches this code path in production.",
  "parent_event_id": "uuid-of-finding"
}
```

- `finding_id` (string): The `id` of the finding being challenged.
- `challenge_type` (enum): One of:
  - `false_positive` — The finding does not describe a real issue.
  - `overstated` — The issue exists but the severity is too high.
  - `missing_context` — The finding overlooks relevant context that changes the assessment.
- `argument` (string): The substantive argument for the challenge.

### `finding_upheld`

A challenged finding is upheld after discussion — the original assessment stands.

```json
{
  "event_id": "uuid",
  "sequence_number": 10,
  "schema_version": "1.0.0",
  "type": "finding_upheld",
  "timestamp": "ISO-8601",
  "agent": "security-reviewer",
  "phase": "discussion",
  "finding_id": "finding-uuid4",
  "supporting_evidence": "The admin migration script is invoked via an API endpoint in src/admin/routes.ts:23. The endpoint accepts a table_name parameter that flows into the raw SQL. This is reachable in production.",
  "parent_event_id": "uuid-of-challenge"
}
```

- `finding_id` (string): The `id` of the finding being upheld.
- `supporting_evidence` (string): Evidence that the original finding is valid despite the challenge.

### `finding_withdrawn`

A finding is withdrawn by its author or by moderator consensus — the issue is dismissed.

```json
{
  "event_id": "uuid",
  "sequence_number": 11,
  "schema_version": "1.0.0",
  "type": "finding_withdrawn",
  "timestamp": "ISO-8601",
  "agent": "performance-reviewer",
  "phase": "discussion",
  "finding_id": "finding-uuid4-b",
  "reason": "After reviewing the benchmark data provided by reliability-reviewer, the N+1 query is mitigated by Prisma's built-in dataloader. The performance impact is negligible at current scale.",
  "parent_event_id": "uuid-of-challenge"
}
```

- `finding_id` (string): The `id` of the finding being withdrawn.
- `reason` (string): Why the finding was withdrawn.

### `finding_modified`

A finding's severity is changed after discussion — the issue is real but the severity was wrong.

```json
{
  "event_id": "uuid",
  "sequence_number": 12,
  "schema_version": "1.0.0",
  "type": "finding_modified",
  "timestamp": "ISO-8601",
  "agent": "security-reviewer",
  "phase": "discussion",
  "finding_id": "finding-uuid4-c",
  "original_severity": "critical",
  "new_severity": "major",
  "reason": "The endpoint requires admin authentication, reducing exploitability. Downgrading from critical to major since the attack surface is limited to authenticated admins.",
  "parent_event_id": "uuid-of-challenge"
}
```

- `finding_id` (string): The `id` of the finding being modified.
- `original_severity` (enum): The severity before modification.
- `new_severity` (enum): The severity after modification.
- `reason` (string): Why the severity was changed.

### `finding_merged`

Multiple findings are merged into a single finding during synthesis — they describe the same underlying issue from different angles.

```json
{
  "event_id": "uuid",
  "sequence_number": 16,
  "schema_version": "1.0.0",
  "type": "finding_merged",
  "timestamp": "ISO-8601",
  "phase": "synthesis",
  "finding_ids": ["finding-uuid4-d", "finding-uuid4-e"],
  "merged_finding_id": "finding-uuid4-merged",
  "reason": "Both findings identify the same missing input validation in the auth service — one from a security angle, the other from a reliability angle. Merging into a single finding with combined recommendations."
}
```

- `finding_ids` (array of strings): The `id`s of the findings being merged.
- `merged_finding_id` (string): The `id` of the new merged finding.
- `reason` (string): Why the findings were merged.

### `specialist_request`

System recommends a domain specialist based on opening-round findings. For example, if security findings are numerous, a security specialist may be recommended.

```json
{
  "event_id": "uuid",
  "sequence_number": 7,
  "schema_version": "1.0.0",
  "type": "specialist_request",
  "timestamp": "ISO-8601",
  "agent": "system",
  "specialist": "cryptography-specialist",
  "justification": "Multiple findings reference custom encryption implementation in auth service"
}
```

- `specialist` (string): The specialist persona identifier.
- `justification` (string): Why this specialist is needed based on opening findings.

### `topic_resolved`

A discussion topic has been resolved or deferred.

```json
{
  "event_id": "uuid",
  "sequence_number": 13,
  "schema_version": "1.0.0",
  "type": "topic_resolved",
  "timestamp": "ISO-8601",
  "id": "T001",
  "status": "resolved",
  "summary": "SQL injection finding upheld at critical severity. The raw SQL endpoint is reachable in production via admin API.",
  "round": 1,
  "resolved_by": "discussion",
  "composition_id": null
}
```

- `id` (string): The topic identifier.
- `status` (enum): `resolved` or `deferred`.
- `summary` (string): How the topic was resolved.
- `round` (integer): Which discussion round resolved the topic.
- `resolved_by` (enum): `discussion` (agents converged), `escalation` (user decided), `composition` (child skill resolved via composition protocol), `deferred` (postponed). Defaults to `discussion` for backward compatibility.
- `composition_id` (string or null): If `resolved_by` is `composition`, the `composition_id` linking to the `composition_invoked`/`composition_completed` events. `null` otherwise.

### `escalation`

A deadlocked topic escalated to the user for decision.

```json
{
  "event_id": "uuid",
  "sequence_number": 14,
  "schema_version": "1.0.0",
  "type": "escalation",
  "timestamp": "ISO-8601",
  "topic": "T002",
  "positions": {
    "security-reviewer": "Finding is critical — the endpoint is publicly reachable after auth bypass",
    "reliability-reviewer": "Finding is major at most — auth bypass requires a separate vulnerability"
  },
  "status": "pending"
}
```

- `topic` (string): The topic identifier being escalated.
- `positions` (object): Map of agent name to their position on the deadlocked topic.
- `status` (enum): Always `pending` at creation.

### `escalation_resolved`

User has resolved a deadlocked topic.

```json
{
  "event_id": "uuid",
  "sequence_number": 15,
  "schema_version": "1.0.0",
  "type": "escalation_resolved",
  "timestamp": "ISO-8601",
  "topic": "T002",
  "decision": "Classify as major. The auth bypass is theoretical without a known exploit chain.",
  "decided_by": "user"
}
```

- `topic` (string): The topic identifier that was escalated.
- `decision` (string): The user's decision.
- `decided_by` (enum): Always `user` for escalation resolutions.

### `final_position`

An agent's top findings and recommendations at the end of discussion, summarizing their view of the most important issues.

```json
{
  "event_id": "uuid",
  "sequence_number": 17,
  "schema_version": "1.0.0",
  "type": "final_position",
  "timestamp": "ISO-8601",
  "agent": "security-reviewer",
  "top_findings": [
    "finding-uuid4-a",
    "finding-uuid4-c",
    "finding-uuid4-merged"
  ],
  "recommendations": [
    "Replace all raw SQL with parameterized Prisma queries",
    "Add input validation middleware for admin API endpoints",
    "Implement rate limiting on authentication endpoints"
  ]
}
```

- `agent` (string): The agent providing their final position.
- `top_findings` (array of strings): Finding IDs the agent considers most important, in priority order.
- `recommendations` (array of strings): The agent's top recommendations for the codebase.

## Code-Review `session_start` Extensions

The `session_start` event (defined in shared base) includes these additional fields for code-review:

```json
{
  "review_target": "src/auth/service.ts",
  "review_mode": "diff | module",
  "technologies_detected": ["typescript", "express"]
}
```

- `review_target` (string): The file or directory being reviewed.
- `review_mode` (enum): `diff` (reviewing a specific change) or `module` (reviewing a module holistically).
- `technologies_detected` (array of strings): Technologies identified during recon. May be empty at session start and populated after the recon phase.

## Code-Review `session_end` Extensions

The `session_end` event (defined in shared base) includes these additional fields for code-review:

```json
{
  "findings_critical": 3,
  "findings_major": 7,
  "findings_minor": 12,
  "findings_nit": 5,
  "findings_withdrawn": 2,
  "composition_used": false
}
```

- `findings_critical` (integer): Count of findings with `critical` severity in terminal state (upheld, modified, or merged — not withdrawn).
- `findings_major` (integer): Count of findings with `major` severity in terminal state.
- `findings_minor` (integer): Count of findings with `minor` severity in terminal state.
- `findings_nit` (integer): Count of findings with `nit` severity in terminal state.
- `findings_withdrawn` (integer): Count of findings that were withdrawn during discussion.
- `composition_used` (boolean): Whether skill composition was invoked during the session.

## JSONL Write Semantics

- **Single writer**: The moderator writes ALL events throughout the entire session. No writer handoff.
- **Atomic writes**: Each event batch is serialized with `json.dumps()`, appended with `flush()` + `fsync()` for durability.
- **Sequence numbers**: Monotonically increasing `sequence_number` on every event. Gaps indicate data loss.
- **JSON serialization**: All events MUST use a proper JSON serializer (`python3 -c 'import json; ...'` or equivalent). Never use string concatenation or `echo` with interpolated values — this prevents injection via crafted agent review text.
- **Session complete sentinel**: The moderator writes a `session_complete` event as the **last event before synthesis**. Synthesis agents verify this sentinel exists before producing output.

## Quality Computation

`session_end.quality` is computed deterministically:

| Quality | Condition |
|---|---|
| **Full** | All selected agents completed their reviews AND all findings in terminal state (upheld, withdrawn, modified, or merged) |
| **Partial** | At least `ceil(n/2)` agents completed AND at least 1 finding resolved |
| **Minimal** | Above quorum (2 agents) but below Partial thresholds |

Where `n` is the number of agents in `session_start.agents`. A finding is in "terminal state" when it has been upheld, withdrawn, modified, or merged. Unchallenged findings from the opening phase are implicitly upheld.

## Cross-Session Manifest Schema

Each entry in `~/.claude/code-review-sessions/manifest.jsonl` includes all common manifest fields (defined in `~/.claude/skills/shared/event-schemas-base.md`) plus these domain-specific fields:

```json
{
  "session_id": "code-review-{target}-{timestamp}",
  "timestamp": "ISO-8601",
  "review_target": "src/auth/service.ts",
  "review_mode": "diff | module",
  "tier": "quick | standard | deep",
  "agent_count": 6,
  "specialist_count": 0,
  "quality": "Full | Partial | Minimal",
  "duration_seconds": 300,
  "technologies_detected": ["typescript", "express"],
  "findings_critical": 0,
  "findings_major": 0,
  "findings_minor": 0,
  "findings_nit": 0,
  "findings_withdrawn": 0,
  "composition_used": false,
  "feedback_actionable": null,
  "feedback_rating": "very_helpful | somewhat_helpful | not_helpful | null"
}
```

- `review_target` (string): The file or directory that was reviewed.
- `review_mode` (string): `diff` or `module`.
- `technologies_detected` (array of strings): Technologies identified during recon.
- `findings_critical` (integer): Count of critical-severity findings in terminal state.
- `findings_major` (integer): Count of major-severity findings in terminal state.
- `findings_minor` (integer): Count of minor-severity findings in terminal state.
- `findings_nit` (integer): Count of nit-severity findings in terminal state.
- `findings_withdrawn` (integer): Count of withdrawn findings.
- `composition_used` (boolean): Whether skill composition was invoked.
- `feedback_actionable` (string or null): Nullable freeform feedback text about actionability of findings. Populated after user provides post-review feedback.
