# Code Review Board — Design Document

**Date:** 2026-03-01
**Status:** Approved
**Skill:** `code-review`

## Overview

Multi-perspective code review skill using Spectra's blackboard architecture.
Multiple specialized reviewer agents independently analyze code, then debate
findings in discussion rounds. A reconnaissance phase gathers codebase context
and current best practices before reviewers begin.

### Input Modes

- **Diff mode:** Branch name or commit range. Scout gathers the diff +
  surrounding context.
- **Module mode:** File or directory path. Scout gathers the module + its
  dependents/dependencies.

## Phases

### Phase 1 — Reconnaissance (two steps)

**Step 1 — Scout (sonnet, Explore agent):**

Explores codebase, produces `recon/context-bundle.json`:

- Target code identification
- Related files and dependency relationships
- Test coverage summary
- Codebase conventions detected
- Technologies and versions detected

**Step 2 — Research (sonnet, general-purpose agent):**

Reads detected technologies from context bundle, does high-level web search
for current-year best practices, deprecation notices, and known issues.
Produces `recon/research-brief.json`.

The research agent stays broad — a survey, not a deep dive. Individual
reviewer agents can do their own targeted web searches during the opening
phase when they hit something specific.

**Tier behavior:** Quick tier skips the research step.

### Phase 2 — Opening Review

4-8 reviewer agents (opus) independently produce findings. Each reads the
context bundle + research brief + target code and reviews from their assigned
perspective. Reviewers have WebSearch access for targeted deep dives.

### Phase 3 — Discussion

Fresh agents (opus) debate contested findings. Moderator extracts disagreements
into topics. Reviewers argue for/against, producing `finding_challenged`,
`finding_upheld`, or `finding_withdrawn` events. Discussion agents do not have
WebSearch — debate is based on evidence already gathered.

### Phase 4 — Final Positions

Each reviewer's top findings after debate, with severity, confidence, and
file:line references.

### Phase 5 — Synthesis

Single agent (sonnet) produces `review-findings.md` — a deduplicated,
severity-ranked findings list.

## Cost Tiers

| Tier | Scout | Research | Reviewers | Discussion Rounds | Output |
|---|---|---|---|---|---|
| Quick | 1 (sonnet) | Skip | 3-4 (opus) | 0 | Findings list |
| Standard | 1 (sonnet) | 1 (sonnet) | 5-6 (opus) | 1 | Findings list |
| Deep | 1 (sonnet) | 1 (sonnet) | 7-8 (opus) | 2 | Findings list |

## Model Allocation

| Agent | Model | Reasoning |
|---|---|---|
| Scout | sonnet | Needs judgment about relevance, not deep reasoning |
| Research | sonnet | Query formulation and summarization |
| Opening reviewers | opus | Nuanced code analysis — quality matters most here |
| Discussion agents | opus | Argumentation and trade-off reasoning |
| Synthesis | sonnet | Structural work — ranking, formatting, dedup |

## Personas

### Core Reviewers (6)

| Persona | Focus | Catches |
|---|---|---|
| Design Critic | Coupling, cohesion, abstractions, SOLID, naming | Leaky abstractions, god classes, poor boundaries |
| Performance Analyst | Algorithmic complexity, memory, I/O, caching | N+1 queries, unnecessary allocations, missing indexes |
| Reliability Engineer | Error handling, edge cases, failure modes | Unhandled errors, race conditions, missing retries |
| Security Auditor | Input validation, auth, data exposure, injection | OWASP top 10, secret leakage, privilege escalation |
| Test Strategist | Coverage gaps, test quality, edge case testing | Missing tests, brittle assertions, untested error paths |
| Maintainability Advocate | Readability, documentation, complexity metrics | Unclear intent, deep nesting, magic numbers, dead code |

### Specialists (invoked on-demand)

| Specialist | Triggered When |
|---|---|
| Database Expert | SQL, ORM code, migrations detected |
| API Designer | HTTP handlers, route definitions, schema files |
| Concurrency Expert | Threads, async/await, locks, channels detected |
| Frontend Architect | React/Vue/Svelte components, CSS, DOM manipulation |
| Infrastructure Reviewer | Dockerfiles, CI configs, IaC templates |
| Accessibility Auditor | HTML, ARIA attributes, UI components |

Specialist recommendation follows the same pattern as deep-design: the
moderator suggests specialists based on technologies detected by the scout.

## Domain Events

Defined in `code-review/event-schemas.md`, inheriting common base events
from `shared/event-schemas-base.md`.

| Event | Phase | Key Fields |
|---|---|---|
| `recon_complete` | Recon | `technologies_detected`, `files_mapped`, `test_coverage_summary` |
| `research_complete` | Recon | `technologies_researched`, `advisories_found`, `deprecations_found` |
| `finding` | Opening | `severity`, `category`, `file_path`, `line_range`, `description`, `recommendation`, `confidence`, `references` |
| `finding_challenged` | Discussion | `finding_id`, `challenge_type`, `argument` |
| `finding_upheld` | Discussion | `finding_id`, `supporting_evidence` |
| `finding_withdrawn` | Discussion | `finding_id`, `reason` |
| `finding_merged` | Synthesis | `finding_ids`, `merged_finding_id` |

### Severity Levels

`critical` > `major` > `minor` > `nit`

### Categories

`design`, `performance`, `security`, `reliability`, `testing`, `maintainability`

## Agent Data Flow

### Scout Output — `recon/context-bundle.json`

```json
{
  "target": { "mode": "diff|module", "path": "...", "diff_range": "..." },
  "technologies": ["react@18.3", "typescript@5.4", "express@4.21"],
  "files": {
    "primary": ["src/auth/service.ts"],
    "related": ["src/auth/types.ts", "src/auth/middleware.ts"],
    "tests": ["tests/auth/service.test.ts"],
    "config": ["tsconfig.json"]
  },
  "conventions": {
    "patterns": ["barrel exports", "dependency injection", "result types"],
    "test_framework": "vitest",
    "style": "functional, minimal classes"
  },
  "test_coverage": { "has_tests": true, "test_count": 12, "gaps": ["error paths untested"] }
}
```

### Research Output — `recon/research-brief.json`

```json
{
  "technologies": {
    "express@4.21": {
      "current_best_practices": ["use native fetch over axios"],
      "deprecations": ["body-parser is built-in since 4.16"],
      "known_issues": [],
      "references": ["https://..."]
    }
  }
}
```

### Reviewer Output — `opening/{reviewer-name}.json`

```json
{
  "reviewer": "performance-analyst",
  "findings": [
    {
      "id": "PA-1",
      "severity": "major",
      "category": "performance",
      "file_path": "src/auth/service.ts",
      "line_range": [42, 58],
      "title": "Unbounded query in user lookup",
      "description": "...",
      "recommendation": "...",
      "confidence": "high",
      "references": ["https://..."]
    }
  ]
}
```

### Discussion Output — `discussion/round-{n}/{reviewer-name}.json`

Contains `finding_challenged`, `finding_upheld`, or `finding_withdrawn` entries.

### Synthesis Output — `review-findings.md`

Deduplicated, severity-ranked findings list with file:line references,
recommendations, debate notes, and research references.

## Session Directory Layout

```
~/.claude/code-review-sessions/{target}-{timestamp}/
  session.lock
  event-log.jsonl
  session-state.md
  handoff.md
  recon/
    context-bundle.json
    research-brief.json
  opening/
    {reviewer-name}.json
  discussion/round-{n}/
    {reviewer-name}.json
  final-positions/
    {reviewer-name}.json
  review-findings.md
  composition-request.json        # Optional
```

## Composition

When reviewers deadlock on a finding, the moderator can invoke decision-board
via the existing composition protocol:

1. Moderator detects deadlock (finding challenged, upheld, challenged again)
2. User approval gate
3. Writes `composition-request.json` with contested finding as decision question
4. Decision-board runs one tier below parent
5. Result returns as `synthesis-brief.json`
6. Finding updated with decision outcome

Max 1 composition per session. Same sequential execution pattern as
deep-design composition.

## Manifest Entry

Appended to `~/.claude/code-review-sessions/manifest.jsonl`.

Shared base fields plus domain-specific:

| Field | Type | Description |
|---|---|---|
| `review_target` | string | File path, directory, or branch diff |
| `review_mode` | string | `diff` or `module` |
| `technologies_detected` | string[] | From scout |
| `findings_critical` | number | Count by severity |
| `findings_major` | number | |
| `findings_minor` | number | |
| `findings_nit` | number | |
| `findings_withdrawn` | number | Retracted during discussion |
| `composition_used` | boolean | Whether decision-board was invoked |

## Prior Session Context

When reviewing the same project again, the moderator loads the most recent
handoff. Reviewers see prior findings (e.g., "last review flagged coupling
in the auth module — was it addressed?"). Follows the existing 2000-char cap
with content sanitization.
