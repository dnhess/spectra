# Spectra — Project Overview

> Multi-agent deliberation skills platform for Claude Code.
> Orchestrates structured review and debate sessions using a blackboard architecture.

**Version:** 0.3.0
**License:** MIT
**Repository:** [https://github.com/dnhess/spectra](https://github.com/dnhess/spectra)

---

## What It Does

Spectra provides three Claude Code skills that stress-test ideas, designs, and code from multiple expert perspectives before implementation or commit. Each skill spawns a panel of specialist agents who review independently, debate across discussion rounds, and produce a synthesized output.

**Core Philosophy:** Every perspective refracted, every angle examined.

---

## The Three Skills

### `deep-design` (v4.0)
Rigorous multi-perspective **design review** for documents, specs, architecture proposals, and feature proposals. Agents review independently, debate, and produce a revised document incorporating all findings.

- **12 core reviewers:** Product Manager, Security Expert, System Architect, Backend Engineer, QA Expert, DevOps Engineer, Data Engineer, Frontend Engineer, Technical Writer, CEO/Strategist, End-User Advocate, Product Designer
- **10 specialist reviewers:** Accessibility Auditor, API Designer, Concurrency Expert, Database Expert, Frontend Architect, Infrastructure Reviewer, Load-Testing SRE, and more
- **Output:** Revised document with tracked changes + synthesis brief

### `decision-board` (v2.0)
Structured multi-perspective **debate** for architectural decisions, technology selection, build-vs-buy, migration strategy. Agents take stances, challenge each other, make concessions, and converge toward an Architecture Decision Record (ADR).

- **7 core debaters:** Architect, Pragmatist, Devil's Advocate, End-User Advocate, Legal Counsel, DevOps Operator, Risk Assessor
- **9 specialist debaters:** Technical Writer, Security Expert, Performance SRE, API Designer, Distributed Systems Expert, Migration Expert, and more
- **Output:** ADR with rationale, alternatives considered, and dissenting views

### `peer-review` (v1.0)
Multi-perspective **code review** for PRs, feature branches, and module rewrites. Includes a unique reconnaissance phase (Scout + Research) that gathers codebase context and best practices before reviewers begin.

- **6 core reviewers:** Reliability Engineer, Security Auditor, Performance Analyst, Design Critic, Maintainability Advocate, Test Strategist
- **6 specialist reviewers:** Accessibility Auditor, API Designer, Concurrency Expert, Database Expert, Frontend Architect, Infrastructure Reviewer
- **Output:** Prioritized findings with recommended actions

### Cost Tiers (all three skills)

| Tier | Use Case |
|---|---|
| **Quick** | Short docs, simple decisions, small diffs — auto-selected |
| **Standard** | Medium complexity — default for most work |
| **Deep** | Large specs, high-stakes decisions, major refactors |

---

## Architecture — Blackboard Pattern

**Key innovation:** No coordinator agent. No `SendMessage` for agent-to-agent coordination. All communication is file-based.

```
Spawned Agents ──(Write JSON)──► Session Directory ◄──(Glob/Read)── Moderator (You)
```

- **Moderator** (main Claude instance) drives every phase directly — spawns agents, polls for files, writes JSONL event log, produces synthesis
- **Agents** work independently and write structured JSON files to session subdirectories
- **Fresh agents per round** — each discussion/debate round spawns new agents rather than reusing previous ones, guaranteeing message delivery
- **No coordinator failures** — file writes are guaranteed; no SendMessage drops

### Session Directory Structure

```
~/.spectra/sessions/{skill}/{topic}-{timestamp}/
  session.lock                  # TTL-based lock
  {skill}-events.jsonl          # Moderator-written event log
  synthesis-brief.json          # Moderator summary of agent outputs
  session-state.md              # Compaction-resilient checkpoint
  handoff.md                    # Cross-session continuity
  opening/
    {agent-name}.json           # Agent opening outputs
  discussion/
    round-{n}/
      {agent-name}.json         # Agent discussion responses
      round-brief.json          # Moderator condensed round summary
  final-positions/
    {agent-name}.json           # Agent final recommendations
```

### Hybrid Storage

- **Files (primary):** JSONL event logs, agent outputs, synthesis brief — active session layer
- **SQLite (`~/.spectra/spectra.db`):** Cross-session metadata (skill, project, tier, quality KPIs, duration) — scaffolded and ready, populated when cross-session query needs emerge

---

## Tech Stack

| Component | Technology |
|---|---|
| **Language** | Bash (CLI + scripts), Python (test helpers) |
| **Testing** | BATS (Bash Automated Testing Framework) — 23 test files |
| **CLI** | `bin/spectra` — 1,146-line bash script |
| **Database** | SQLite WAL mode (`shared/tools/db-utils.sh`) |
| **Session coordination** | JSONL event logs + JSON file polling |
| **Agent mode** | `bypassPermissions` subagent mode for file writes |
| **Package manager** | npm (dev deps: commitlint, husky, markdownlint-cli2, bats) |
| **CI/CD** | GitHub Actions (lint, shellcheck, commitlint, BATS tests, release) |
| **Deployment** | Curl installer; symlinks to `~/.claude/skills/` |

---

## Project Structure

```
spectra/
├── README.md                       # Overview + installation
├── CLAUDE.md                       # Architecture decisions + conventions
├── CHANGELOG.md                    # Release notes
├── package.json                    # npm dev deps
├── bin/
│   ├── spectra                     # Main CLI
│   └── json-write.sh               # Scoped JSON writer (user-facing permission)
├── shared/                         # Reusable orchestration (not a skill itself)
│   ├── orchestration.md            # Blackboard protocol, session lifecycle
│   ├── event-schemas-base.md       # Common JSONL event types
│   ├── composition.md              # Inter-skill invocation protocol
│   ├── security.md                 # 4-layer defense model
│   ├── tools/
│   │   ├── jsonl-utils.sh          # JSONL query utility
│   │   ├── db-utils.sh             # SQLite operations
│   │   └── validate-output.sh      # 5-stage validation pipeline
│   └── schemas/                    # 6 JSON validation schemas
├── deep-design/
│   ├── SKILL.md                    # Full orchestration spec
│   ├── event-schemas.md            # Domain-specific events
│   └── personas/                   # 12 core + 10 specialist reviewers
├── decision-board/
│   ├── SKILL.md                    # Full orchestration spec
│   ├── event-schemas.md            # Domain-specific events
│   └── personas/                   # 7 core + 9 specialist debaters
├── peer-review/
│   ├── SKILL.md                    # Full orchestration spec (78 KB)
│   ├── event-schemas.md            # Domain-specific events
│   └── personas/                   # 6 core + 6 specialist reviewers
├── test/                           # 23 BATS test files
│   ├── *.bats
│   ├── helpers/                    # Python validators + BATS setup
│   ├── fixtures/                   # Test data
│   └── test_helper/                # BATS assertion library
└── docs/plans/                     # Strategic design docs
    ├── 2026-03-01-orchestration-hardening-findings.md
    ├── 2026-03-01-product-strategy-directions.md
    ├── 2026-03-02-trust-layer-design.md
    ├── 2026-03-02-trust-layer-implementation.md
    ├── 2026-03-02-coherence-monitor-design.md
    └── 2026-03-02-coherence-monitor-implementation.md
```

---

## Shared Infrastructure

All three skills share a common orchestration backbone in `shared/`:

| File | Purpose |
|---|---|
| `orchestration.md` | Master protocol: blackboard pattern, session lifecycle, agent spawning, context budget monitoring, emergency shutdown, round summarization, compaction recovery |
| `event-schemas-base.md` | Common JSONL event types: `session_start`, `phase_transition`, `agent_complete`, `session_complete`, `session_end`, `context_budget_status`, `security_violation`, `composition_invoked` |
| `security.md` | 4-layer defense model (see below) |
| `composition.md` | Inter-skill invocation protocol (e.g., deep-design → decision-board for deadlocked topics) |
| `validate-output.sh` | 5-stage output validation: size → JSON parse → schema → sanitization → accept |
| `db-utils.sh` | SQLite init, query, execute, integrity check |
| `jsonl-utils.sh` | JSONL count-type, search utilities |

---

## Security Model (4 Layers)

1. **Prompt-level path constraints** — agents told exactly where to write; no other paths
2. **Post-phase directory audit** — moderator diffs file list against allowlist after each phase
3. **Content sanitization** — scans for injection patterns (markdown headers in text fields, system prompt fragments, tool invocation patterns)
4. **Web content isolation** — WebSearch output tagged with `source_url` + `retrieved_at`; domain scoping enforced

---

## Agent Spawning

All agents are spawned as:
- `subagent_type`: `"general-purpose"`
- `mode`: `"bypassPermissions"` (required for session directory writes)
- `run_in_background`: `true` (concurrent execution per phase)

**Model allocation:**
- Opening / scout / research phases → Opus (analysis-heavy)
- Discussion / final positions / synthesis → Sonnet (sufficient, lower cost)
- Deep tier may use Opus for discussion depending on domain

---

## Output Validation Pipeline

All agent outputs go through 5 stages before the moderator writes them to the event log:

```
1. Size check (≤50 KB)
2. JSON parse (valid syntax)
3. Schema validation (required fields per phase + skill)
4. Content sanitization (injection pattern scan)
5. Accept (all stages passed)
```

Exit codes: `0` valid, `1` invalid (drop output), `2` warn-only.

---

## Quality KPIs

Tracked in SQLite at session end:

| KPI | Skill | Description |
|---|---|---|
| `completion_rate` | All | % of phases completed |
| `security_violations_count` | All | Layer 2/3 violations |
| `convergence_rate` | deep-design | % of topics reaching consensus |
| `specialist_utilization` | deep-design | % of specialists spawned |
| `concessions_count` | decision-board | Genuine debate indicator |
| `consensus_strength` | decision-board | Unanimous vs. fractured agreement |
| `rounds_debated` | decision-board | Iterations before convergence |

---

## Installation & Management

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/dnhess/spectra/main/install.sh | bash

# Manage
spectra status      # Installation info + version
spectra update      # Update to latest release
spectra doctor      # Diagnose issues (symlinks, permissions, SQLite health)
spectra link .      # Dev mode: symlink repo to ~/.claude/skills/
spectra uninstall   # Remove Spectra
```

Installation creates:
- `~/.spectra/` — sessions, database, config
- `~/.claude/skills/` — symlinks to each skill
- Permissions entry in `~/.claude/settings.json` for session directory writes

---

## Testing

```bash
npm test            # Run all 23 BATS test suites
```

Test coverage:
- CLI: install, update, link, unlink, status, rollback, help, backup
- Infrastructure: JSONL utilities, JSON writer, validation pipeline, db-utils
- Orchestration: event log integrity, session lifecycle, persona loading, security audit
- Advanced: context budget monitoring, quality KPI computation, failure modes, path lint

---

## Key Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Agent coordination | Blackboard (files), not hub-and-spoke | No coordinator failures; guaranteed delivery |
| Event log writer | Moderator only | No ordering violations; single writer authority |
| Agents per round | Fresh spawn | Prevents SendMessage delivery failures |
| SQLite activation | Scaffolded but not populated | Activate when a concrete cross-session query need emerges |
| Composition | User-gated, max 1 per session | Never auto-invoke; user always approves |
| Context tracking | Proxy metrics, not token counts | Platform doesn't expose token counts |
| Heartbeat monitoring | File-existence polling + timeouts | No timer mechanism in Claude Code |

---

## Roadmap

### Direction 1: The Trust Layer (approved, in progress)
Quick-tier adversarial review of AI outputs before code lands in repo. Catches hallucinated packages, intent mismatch, security issues.
- **Output:** Confidence-graded challenges + conditions for acceptance
- **Delivery:** On-demand Spectra skill with clean CLI flags + structured JSON output
- **Plan docs:** `docs/plans/2026-03-02-trust-layer-design.md`, `trust-layer-implementation.md`

### Direction 2: The Coherence Monitor (design approved, sequenced after Direction 1)
Metacognitive checkpointing for long-running agents — "Am I still solving the right problem?"
- **Detects:** Drift, constraint violations, goal misalignment
- **Personas:** Alignment Auditor, Contradiction Detector, Constraint Monitor, Devil's Examiner
- **Tiers:** Quick (30–45s), Standard (~2 min), Deep (~5 min)
- **Plan docs:** `docs/plans/2026-03-02-coherence-monitor-design.md`, `coherence-monitor-implementation.md`

### Direction 3: Deliberation as Infrastructure (concept)
MCP server exposing deliberation capabilities to any agent, model, or tool — beyond Claude Code.

---

## CI/CD Guardrails

GitHub Actions blocks merge if:
- Markdown lint fails (markdownlint-cli2)
- ShellCheck fails on any `.sh` file
- Conventional commit format violated
- `CHANGELOG.md` not updated for skill/infrastructure changes
- Changes to `shared/`, `install.sh`, `SKILL.md`, or event-schemas without CODEOWNERS review

---

## Key Files Reference

| File | Purpose |
|---|---|
| `bin/spectra` | Main CLI — install, update, link, doctor, status |
| `shared/orchestration.md` | Master blackboard protocol (36 KB) |
| `shared/event-schemas-base.md` | Common JSONL event types (17.5 KB) |
| `shared/security.md` | 4-layer defense model |
| `shared/composition.md` | Inter-skill invocation protocol |
| `shared/tools/validate-output.sh` | 5-stage validation pipeline |
| `deep-design/SKILL.md` | Deep design skill full spec |
| `decision-board/SKILL.md` | Decision board skill full spec |
| `peer-review/SKILL.md` | Code review skill full spec (78 KB) |
| `docs/plans/2026-03-01-product-strategy-directions.md` | Strategic direction analysis |
