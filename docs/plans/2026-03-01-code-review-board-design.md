# Code Review Board — Design Document

**Date:** 2026-03-01
**Status:** Revised (post-review)
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

## User Journey

[Added per review: T004]

Invocation: `/review [path-or-branch] [--tier quick|standard|deep]`

**Invocation flow:**

1. User runs slash command with target and optional tier flag.
2. If no tier flag, moderator applies auto-selection criteria (see Tier Auto-Selection).
3. Moderator displays: target summary, detected technologies (post-scout), proposed
   reviewer roster, estimated cost tier. Prompts for confirmation before spawning opus agents.
4. **Post-recon gate:** After Phase 1, moderator shows scout summary and research
   highlights. User confirms or adjusts roster before Phase 2 begins.
5. **Discussion controls (Standard/Deep only):**
   - Press Enter — advance to next topic
   - `i` — dismiss as false positive (withdraws finding, logged)
   - `w` — wrap up discussion early, proceed to final positions
6. **Post-session feedback:** Micro-survey matching deep-design pattern.
   "Were these findings actionable? (y/n)" — result written to manifest.

## Tier Auto-Selection

[Added per review: T004]

When no `--tier` flag is provided, moderator selects based on target size:

| Criteria | Tier |
|---|---|
| Single file or < 200 lines changed | Quick |
| 200–1000 lines or 2–4 files | Standard |
| > 1000 lines or 5+ files | Deep |

User can override the auto-selected tier at the confirmation gate.

## Phases

### Phase 1 — Reconnaissance (two steps)

**Step 1 — Scout (sonnet, general-purpose agent):** [Added per review: T001]

General-purpose agent with read-boundary constraints in prompt: project directory
only, no dotfiles, no .git internals. Explores codebase, produces
`recon/context-bundle.json`:

- Target code identification
- Related files and dependency relationships
- Test coverage summary
- Codebase conventions detected
- Technologies and versions detected (structured format: {name, version, source, confidence})

**Step 2 — Research (sonnet, general-purpose agent):**

Reads detected technologies from context bundle, does high-level web search
for current-year best practices, deprecation notices, and known issues.
Two-pass pattern: collect raw results, then sanitize before writing to
`recon/research-brief.json`. All web-sourced content is tagged with provenance.
Research agent uses domain scoping in search prompts (authoritative docs only).
Content is treated as untrusted external input with randomized delimiters.

The research agent stays broad — a survey, not a deep dive. Individual
reviewer agents can do their own targeted web searches during the opening
phase when they hit something specific.

**Tier behavior:** Quick tier skips the research step.

**Post-recon checkpoint:** [Added per review: T005] A checkpoint is written after
Phase 1 completes. The moderator shows scout summary, research highlights, and
proposed reviewer roster before proceeding to Phase 2.

### Phase 2 — Opening Review

4-8 reviewer agents (opus) independently produce findings. Each reads the
context bundle + research brief + target code and reviews from their assigned
perspective. Reviewers have WebSearch access for targeted deep dives.

**WebSearch constraints (prompt-level):** [Added per review: T002] Do not include
source code or internal identifiers in search queries. Domain scoping to
authoritative sources only.

### Phase 3 — Discussion

Fresh agents (opus) debate contested findings. Moderator extracts disagreements
into topics. Reviewers argue for/against, producing `finding_challenged`,
`finding_upheld`, or `finding_withdrawn` events. Discussion agents do not have
WebSearch — debate is based on evidence already gathered.

**Skipped in Quick tier.** [Added per review: T005]

### Phase 4 — Final Positions

Each reviewer's top findings after debate, with severity, confidence, and
file:line references.

**Skipped in Quick tier.** Quick tier flow: Recon -> Opening -> Synthesis. [Added per review: T005]

### Phase 5 — Synthesis

Single agent (sonnet) produces `review-findings.md` — a deduplicated,
severity-ranked findings list. Merge semantics: highest severity wins, all
unique recommendations kept, merge noted in output. [Added per review: T003]

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

## Finding Lifecycle

[Added per review: T003]

### State Machine

```
open -> challenged -> upheld
                   -> withdrawn
                   -> modified
```

- **open:** Finding published by reviewer in opening phase.
- **challenged:** Another reviewer disputes the finding in discussion.
- **upheld:** Original author defends finding successfully.
- **withdrawn:** Original author retracts the finding (only the original author
  may withdraw or modify; third parties may only challenge).
- **modified:** Original author accepts partial challenge and updates severity/recommendation.

Each challenge is resolved independently. One consolidated response per round per finding.

### Finding IDs

[Added per review: T003]

Format: `finding-{uuid4}`. The moderator assigns short display aliases
(e.g., "F1", "F2") for readability in discussion. The UUID is the canonical
cross-reference.

### Confidence Behavior

[Added per review: T004] The `confidence` field (high/medium/low) affects synthesis
ranking. Low-confidence findings are deprioritized and flagged. High-confidence
findings are promoted in the severity-ranked output.

## Deadlock Detection

[Added per review: T006]

**Per-finding:** A finding is declared deadlocked when it has accumulated 2 or more
challenge-upheld cycles (challenged, then upheld, then challenged again).

**Session-level circuit breaker:** If 30% or more of open findings are deadlocked,
the session-level circuit breaker triggers and the moderator offers composition
to the user.

**Algorithm:**

```
for each finding f:
    if count(challenge_upheld_cycles on f) >= 2:
        mark f as deadlocked

deadlock_ratio = deadlocked_findings / open_findings
if deadlock_ratio >= 0.30:
    trigger composition gate (user approval required)
else:
    offer composition only for individually deadlocked findings
```

Max 1 composition per session.

## Web Search Security

[Added per review: T002]

WebSearch is a new trust boundary. The following controls apply:

- **Provenance tagging:** All web-sourced content in `research-brief.json` carries
  a `source_url` and `retrieved_at` timestamp. Reviewers are instructed to label
  web-sourced claims in findings.
- **Domain scoping:** Research and reviewer prompts include an authoritative-domain
  allowlist. Agents are instructed not to follow redirect chains to unknown domains.
- **Content isolation:** Web content is treated as untrusted external input.
  Randomized delimiters separate web content from agent instructions.
- **Two-pass research:** Research agent collects raw results, then runs a sanitization
  pass before writing to `research-brief.json`.
- **Query constraints:** Reviewer agents are prompt-instructed not to include source
  code, internal identifiers, or session IDs in search queries.
- **URL validation:** Synthesis agent flags references pointing to unrecognized domains
  with an "unverified source" caveat.
- **Layer 4 addition:** `shared/security.md` must be updated to document WebSearch as
  Layer 4: Web Content Isolation.

## Phase Boundary Validation

[Added per review: T005]

JSON schema validation is applied at each phase boundary. The moderator validates
agent output before advancing to the next phase.

| Boundary | Required Fields | Action on Failure |
|---|---|---|
| Recon -> Opening | `technologies`, `files.primary` in context-bundle | Abort session, surface error |
| Opening -> Discussion | `findings` array non-empty, each finding has `id`, `severity`, `file_path` | Skip findings with missing required fields |
| Discussion -> Final Positions | All referenced `finding_id` values exist in opening output | Reject orphan events |
| Final Positions -> Synthesis | At least one finding in `open` or `upheld` state | Warn if empty, continue |

Technology strings from context-bundle are validated with regex:
`^[a-zA-Z0-9._-]{1,100}$`. Non-conforming entries are stripped before
passing to the research agent. [Added per review: T005]

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
  "technologies": [
    { "name": "react", "version": "18.3", "source": "package.json", "confidence": "high" }
  ],
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

Technology format changed to structured objects. [Added per review: T003]

### Research Output — `recon/research-brief.json`

```json
{
  "technologies": {
    "express@4.21": {
      "current_best_practices": ["use native fetch over axios"],
      "deprecations": ["body-parser is built-in since 4.16"],
      "known_issues": [],
      "references": [{ "url": "https://...", "retrieved_at": "2026-03-01T16:05:14Z" }]
    }
  }
}
```

All references carry provenance metadata. [Added per review: T002]

### Reviewer Output — `opening/{reviewer-name}.json`

```json
{
  "reviewer": "performance-analyst",
  "findings": [
    {
      "id": "finding-a3f1c2d4-e5f6-7890-abcd-ef1234567890",
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

Finding IDs use UUID format. [Added per review: T003]

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

The `recon/` directory is in the Layer 2 security audit allowlist. [Added per review: T005]
Session directory name is sanitized: path separators stripped, special chars replaced
with `-`, truncated to 40 chars. [Added per review: T005]

## Composition

When reviewers deadlock on a finding, the moderator can invoke decision-board
via the existing composition protocol:

1. Moderator detects deadlock via count-based algorithm (see Deadlock Detection).
2. User approval gate.
3. Writes `composition-request.json` with contested finding as decision question.
4. Decision-board runs one tier below parent.
5. Result returns as `synthesis-brief.json`.
6. Finding updated with decision outcome.

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
| `feedback_actionable` | boolean | Post-session micro-survey result |

## Prior Session Context

When reviewing the same project again, the moderator loads the most recent
handoff. Reviewers see prior findings (e.g., "last review flagged coupling
in the auth module — was it addressed?"). Follows the existing 2000-char cap
with content sanitization.

The handoff includes the commit hash at which the prior review was conducted. [Added per review: T003]
Reviewers are instructed to verify prior file:line references against the current
diff before citing them, as code evolves between reviews.

## Success Metrics

[Added per review: T004]

| Metric | Definition | Target |
|---|---|---|
| Findings-to-action rate | Fraction of critical/major findings that result in a code change (measured via follow-up review) | > 60% |
| False-positive rate | Fraction of findings dismissed as false positives via `i` during discussion | < 20% |
| Session completion rate | Sessions that reach synthesis without abort | > 90% |
| User satisfaction | Post-session feedback "actionable?" yes rate | > 70% |

Metrics are aggregated from manifest entries and feedback events over rolling 30-day windows.

## Deployment Checklist

[Added per review: T005]

Before shipping the code-review skill:

- [ ] Add `code-review` entry to `install.sh` symlink table
- [ ] Update `shared/security.md` to add Layer 4 (Web Content Isolation)
- [ ] Add `recon/` to Layer 2 directory allowlist in `shared/security.md`
- [ ] Create `code-review/event-schemas.md` referencing `shared/event-schemas-base.md`
- [ ] Create `code-review/personas/` directory with 6 core persona files
- [ ] Add CHANGELOG.md entry under `[Unreleased]`
- [ ] Verify ShellCheck passes on any new `.sh` files
- [ ] Run `npm run lint` to confirm markdown lint passes
- [ ] Smoke test Quick tier on a single-file diff
- [ ] Smoke test recon directory audit (confirm no false security violations)
