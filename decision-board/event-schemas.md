# Event Schemas — Decision Board

This file defines domain-specific event types for decision-board. For common event types (session_start, phase_transition, agent_complete, session_complete, session_end, feedback, security_violation), see `~/.claude/skills/shared/event-schemas-base.md`.

## Domain Event Types

### `stance`

An agent's opening position on the decision question. Produced during the POSITIONING phase.

```json
{
  "event_id": "uuid",
  "sequence_number": 2,
  "schema_version": "1.0.0",
  "type": "stance",
  "timestamp": "ISO-8601",
  "agent_id": "backend-engineer",
  "preferred_option": "monorepo",
  "confidence": 0.75,
  "conditions": [
    "Only if we invest in proper build tooling (Turborepo or Nx)",
    "Requires shared lint and test config from day one"
  ],
  "reasoning": "A monorepo reduces cross-service integration friction and enables atomic refactors across the API and frontend layers. With only 5 engineers, the coordination overhead of multiple repos outweighs the isolation benefit.",
  "options_assessed": [
    {
      "option": "monorepo",
      "assessment": "Best fit for small team. Atomic changes, shared tooling. Risk: build times at scale."
    },
    {
      "option": "polyrepo",
      "assessment": "Strong isolation but heavy coordination tax for a 5-person team. CI/CD duplication."
    },
    {
      "option": "hybrid",
      "assessment": "Theoretically appealing but adds complexity without clear benefit at our current scale."
    }
  ]
}
```

- `preferred_option` (string): The option this agent recommends.
- `confidence` (float, 0.0-1.0): How strongly the agent holds this position. 1.0 = near-certain, 0.5 = coin flip with slight lean.
- `conditions` (array of strings): Prerequisites or caveats for the recommendation.
- `reasoning` (string): The core argument supporting this position.
- `options_assessed` (array of objects): Brief assessment of each option considered, showing the agent evaluated alternatives.

### `challenge`

An agent challenges another agent's stance during the DEBATING phase.

```json
{
  "event_id": "uuid",
  "sequence_number": 6,
  "schema_version": "1.0.0",
  "type": "challenge",
  "timestamp": "ISO-8601",
  "agent_id": "devops-engineer",
  "target_agent": "backend-engineer",
  "target_stance": "uuid-of-stance-event",
  "challenge_type": "operational_burden",
  "argument": "Monorepo CI pipelines at even moderate scale require significant build infrastructure investment. With a 2-week CI/CD deadline, you will not have time to configure proper caching and selective builds. Every PR will trigger full-repo CI, destroying developer velocity.",
  "evidence": "Our current Jenkins setup has no monorepo-aware build graph. Turborepo remote caching requires a paid plan or self-hosted infra.",
  "impact_on_own_stance": "strengthened",
  "parent_event_id": "uuid-of-stance-event"
}
```

- `target_agent` (string): The agent whose stance is being challenged.
- `target_stance` (string, UUID): Reference to the specific `stance` event being challenged.
- `challenge_type` (enum): One of:
  - `technical_flaw` — The proposed approach has a technical deficiency.
  - `missing_context` — The stance overlooks relevant information.
  - `cost_underestimate` — Implementation or operational cost is higher than claimed.
  - `risk_underestimate` — Risks are more severe or likely than acknowledged.
  - `scalability_concern` — The approach won't hold at expected scale.
  - `operational_burden` — Day-to-day operational cost is unsustainable.
  - `alternative_overlooked` — A better option exists that wasn't considered.
- `argument` (string): The substantive challenge.
- `evidence` (string, optional): Supporting data, references, or concrete examples.
- `impact_on_own_stance` (enum): How making this challenge affects the challenger's own position:
  - `unchanged` — No effect on own stance.
  - `strengthened` — Making this argument reinforced own position.
  - `weakened` — Researching this challenge revealed weaknesses in own position too.
  - `shifted` — This challenge caused the challenger to reconsider (expect a `concession` event to follow).

### `concession`

An agent changes their preferred option. This is the most valuable signal in a debate — it indicates genuine position evolution rather than entrenched arguing.

```json
{
  "event_id": "uuid",
  "sequence_number": 8,
  "schema_version": "1.0.0",
  "type": "concession",
  "timestamp": "ISO-8601",
  "agent_id": "backend-engineer",
  "previous_option": "monorepo",
  "new_option": "hybrid",
  "previous_confidence": 0.75,
  "new_confidence": 0.65,
  "trigger": "devops-engineer's challenge about CI/CD timeline constraint",
  "reasoning": "The 2-week CI/CD constraint is a hard blocker for full monorepo. A hybrid approach — shared libraries in a monorepo with service repos for deployment — gives us atomic changes on shared code while keeping CI simple per-service.",
  "parent_event_id": "uuid-of-challenge-event"
}
```

- `previous_option` (string): The option the agent previously preferred.
- `new_option` (string): The option the agent now prefers.
- `previous_confidence` (float, 0.0-1.0): Confidence before the shift.
- `new_confidence` (float, 0.0-1.0): Confidence in the new position.
- `trigger` (string): What caused the position shift — typically references a specific challenge or argument.
- `reasoning` (string): Why the agent changed position.

### `consensus_check`

Per-round vote tally produced by the moderator to measure convergence. Emitted at the end of each debate round.

```json
{
  "event_id": "uuid",
  "sequence_number": 10,
  "schema_version": "1.0.0",
  "type": "consensus_check",
  "timestamp": "ISO-8601",
  "round_number": 2,
  "votes": [
    { "agent_id": "backend-engineer", "preferred_option": "hybrid", "confidence": 0.65 },
    { "agent_id": "frontend-engineer", "preferred_option": "monorepo", "confidence": 0.60 },
    { "agent_id": "devops-engineer", "preferred_option": "polyrepo", "confidence": 0.70 },
    { "agent_id": "security-engineer", "preferred_option": "hybrid", "confidence": 0.55 }
  ],
  "consensus_strength": 0.50,
  "consensus_option": "hybrid",
  "threshold": 0.75
}
```

- `round_number` (integer): Which debate round this tally summarizes.
- `votes` (array of objects): Each agent's current position and confidence.
- `consensus_strength` (float, 0.0-1.0): Weighted agreement level. Computed as the fraction of agents preferring the plurality option, weighted by confidence.
- `consensus_option` (string or null): The option with plurality support, or `null` if no option has more than one vote.
- `threshold` (float): The consensus strength required to trigger the DECIDING phase. Default is 0.75; may be 0.80 for `deep` tier.

### `decision_proposed`

Emitted when the moderator determines sufficient consensus exists (or debate rounds are exhausted) and proposes a final recommendation.

```json
{
  "event_id": "uuid",
  "sequence_number": 12,
  "schema_version": "1.0.0",
  "type": "decision_proposed",
  "timestamp": "ISO-8601",
  "recommended_option": "hybrid",
  "consensus_strength": 0.78,
  "supporting_agents": ["backend-engineer", "security-engineer", "frontend-engineer"],
  "dissenting_agents": [
    {
      "agent_id": "devops-engineer",
      "preferred_option": "polyrepo",
      "reasoning": "Hybrid adds accidental complexity. Clean polyrepo with a shared package registry achieves the same goals with less tooling magic."
    }
  ],
  "conditions": [
    "Shared libraries monorepo must have independent CI pipeline",
    "Service repos consume shared libs as versioned packages, not git submodules"
  ],
  "risks": [
    "Hybrid requires discipline to keep the boundary clean — risk of monorepo creep",
    "Two CI configurations to maintain instead of one"
  ]
}
```

- `recommended_option` (string): The option recommended by majority.
- `consensus_strength` (float, 0.0-1.0): Final consensus measurement.
- `supporting_agents` (array of strings): Agents backing the recommendation.
- `dissenting_agents` (array of objects): Agents who disagree, with their preferred option and reasoning. Dissent is preserved — it is valuable signal for the ADR.
- `conditions` (array of strings): Prerequisites that must hold for the recommendation to be valid.
- `risks` (array of strings): Known risks of the recommended approach.

### `final_position`

An agent's final recommendation at the end of debate, with ranked assessment of all options.

```json
{
  "event_id": "uuid",
  "sequence_number": 14,
  "schema_version": "1.0.0",
  "type": "final_position",
  "timestamp": "ISO-8601",
  "agent": "backend-engineer",
  "recommendation": "hybrid",
  "confidence": 0.65,
  "conditions": [
    "Shared libs consumed as versioned packages",
    "Independent CI for the shared monorepo"
  ],
  "option_rankings": [
    { "rank": 1, "option": "hybrid", "rationale": "Best balance of code sharing and CI simplicity under our constraints." },
    { "rank": 2, "option": "monorepo", "rationale": "Ideal long-term but infeasible within the 2-week CI/CD timeline." },
    { "rank": 3, "option": "polyrepo", "rationale": "Viable but coordination tax too high for a 5-person team." }
  ]
}
```

- `recommendation` (string): The agent's top pick.
- `confidence` (float, 0.0-1.0): How confident the agent is in this recommendation after debate.
- `conditions` (array of strings): Conditions under which this recommendation holds.
- `option_rankings` (array of objects): All options ranked from most to least preferred, with rationale for each.

## Synthesis Brief Schema

The moderator writes `synthesis-brief.json` to the session directory before the `session_complete` sentinel. The synthesis agents read this to produce the Architecture Decision Record (ADR).

```json
{
  "session_id": "decision-board-{topic}-{timestamp}",
  "decision_question": "Should we use a monorepo or polyrepo for the new platform?",
  "options": ["monorepo", "polyrepo", "hybrid"],
  "constraints": ["must support CI/CD within 2 weeks", "team of 5 engineers"],
  "stances_by_agent": {
    "backend-engineer": {
      "final_option": "hybrid",
      "confidence": 0.65,
      "conditions": ["Shared libs consumed as versioned packages"],
      "position_history": ["monorepo", "hybrid"]
    },
    "frontend-engineer": {
      "final_option": "monorepo",
      "confidence": 0.60,
      "conditions": ["Turborepo with remote caching"],
      "position_history": ["monorepo"]
    },
    "devops-engineer": {
      "final_option": "polyrepo",
      "confidence": 0.70,
      "conditions": ["Shared package registry for common code"],
      "position_history": ["polyrepo"]
    },
    "security-engineer": {
      "final_option": "hybrid",
      "confidence": 0.55,
      "conditions": ["Security-critical shared libs must be in the monorepo portion"],
      "position_history": ["monorepo", "hybrid"]
    }
  },
  "challenges": [
    {
      "challenger": "devops-engineer",
      "target": "backend-engineer",
      "type": "operational_burden",
      "summary": "Monorepo CI infeasible within 2-week constraint",
      "impact": "Caused backend-engineer to shift to hybrid"
    }
  ],
  "concessions": [
    {
      "agent_id": "backend-engineer",
      "from": "monorepo",
      "to": "hybrid",
      "trigger": "CI/CD timeline constraint raised by devops-engineer"
    },
    {
      "agent_id": "security-engineer",
      "from": "monorepo",
      "to": "hybrid",
      "trigger": "Followed backend-engineer's reasoning on timeline"
    }
  ],
  "consensus_strength": 0.78,
  "recommended_option": "hybrid",
  "dissenting_views": [
    {
      "agent_id": "devops-engineer",
      "preferred_option": "polyrepo",
      "reasoning": "Hybrid adds accidental complexity. Clean polyrepo with a shared package registry achieves the same goals with less tooling magic."
    }
  ],
  "conditions_and_assumptions": [
    "Shared libraries monorepo must have independent CI pipeline",
    "Service repos consume shared libs as versioned packages, not git submodules",
    "Team invests in proper build tooling within first sprint"
  ],
  "risks": [
    "Hybrid requires discipline to keep the boundary clean — risk of monorepo creep",
    "Two CI configurations to maintain instead of one",
    "Versioned package consumption adds release ceremony overhead"
  ]
}
```

### Synthesis Brief Fields

| Field | Type | Description |
|---|---|---|
| `session_id` | string | Session identifier |
| `decision_question` | string | The central question debated |
| `options` | array of strings | All options considered |
| `constraints` | array of strings | Hard constraints from session_start |
| `stances_by_agent` | object | Each agent's final stance with position history |
| `challenges` | array of objects | Notable challenges that influenced the debate |
| `concessions` | array of objects | Position shifts — the most valuable signal for the ADR |
| `consensus_strength` | float | Final weighted consensus measurement |
| `recommended_option` | string | The plurality option |
| `dissenting_views` | array of objects | Agents who disagree with the recommendation |
| `conditions_and_assumptions` | array of strings | Aggregated conditions from supporting agents |
| `risks` | array of strings | Aggregated risks identified during debate |

## JSONL Write Semantics

- **Single writer**: The moderator writes all events throughout the entire session. No writer handoff. See `~/.claude/skills/shared/orchestration.md` for the write protocol.
- **Atomic writes**: Each event batch is serialized with `json.dumps()`, appended with `flush()` + `fsync()` for durability.
- **Sequence numbers**: Monotonically increasing `sequence_number` on every event. Gaps indicate data loss.
- **JSON serialization**: All events MUST use a proper JSON serializer (`python3 -c 'import json; ...'` or equivalent). Never use string concatenation or `echo` with interpolated values — this prevents injection via crafted agent output.
- **Session complete sentinel**: The moderator writes a `session_complete` event as the **last event before synthesis**. Synthesis agents verify this sentinel exists before producing output.

## Quality Computation

`session_end.quality` is computed deterministically:

| Quality | Condition |
|---|---|
| **Full** | All selected agents completed all phases AND consensus_strength >= threshold |
| **Partial** | At least `ceil(n/2)` agents completed AND a `decision_proposed` event exists |
| **Minimal** | Above quorum (2 agents) but below Partial thresholds |

Where `n` is the number of agents in `session_start.agents`.

## Cross-Session Manifest Schema

Each entry in `~/.claude/decision-board-sessions/manifest.jsonl` has this schema:

```json
{
  "session_id": "decision-board-{topic}-{timestamp}",
  "timestamp": "ISO-8601",
  "decision_question": "Should we use a monorepo or polyrepo?",
  "options": ["monorepo", "polyrepo", "hybrid"],
  "tier": "quick | standard | deep",
  "agent_count": 4,
  "specialist_count": 1,
  "quality": "Full | Partial | Minimal",
  "duration_seconds": 360,
  "rounds_debated": 3,
  "consensus_strength": 0.78,
  "recommended_option": "hybrid",
  "concessions_count": 2,
  "dissenting_agents_count": 1,
  "feedback_rating": "very_helpful | somewhat_helpful | not_helpful | null",
  "adopted_option": "hybrid | null",
  "parent_composition_id": null,
  "parent_session_id": null
}
```

Fields `feedback_rating` and `adopted_option` are nullable. `feedback_rating` and `adopted_option` are populated after user provides post-decision feedback.

- `parent_composition_id`: If this session was invoked via composition, the `composition_id` from the parent. `null` for standalone sessions.
- `parent_session_id`: If this session was invoked via composition, the parent skill's `session_id`. `null` for standalone sessions.
