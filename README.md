# Spectra

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Lint](https://github.com/dnhess/spectra/actions/workflows/lint.yml/badge.svg)](https://github.com/dnhess/spectra/actions/workflows/lint.yml)

Multi-agent deliberation skills for Claude Code. Orchestrates structured review and debate sessions using a **blackboard architecture** — every perspective refracted, every angle examined.

## Available Skills

### deep-design
**Rigorous multi-perspective design review.** Use when a document, spec, or idea needs stress-testing from every angle before implementation. Produces a revised document with all findings incorporated.

Triggers: design docs, architecture specs, product requirements, feature proposals.

### decision-board
**Structured multi-perspective debate.** Use when a decision needs structured debate before committing. Produces an Architecture Decision Record (ADR) with recommendation, dissent, and conditions.

Triggers: architectural decisions, technology selection, build-vs-buy, migration strategy.

### peer-review
**Multi-perspective code review.** Use when code changes need thorough review from multiple specialist viewpoints before merge. Includes a Scout + Research reconnaissance phase that gathers codebase context and best practices before reviewers begin.

Triggers: pull requests, code changes, refactoring review.

### trust-layer
**Adversarial verification for AI-generated output.** Use before accepting any AI-generated code, diff, file, or Spectra session recommendation. Four adversarial personas (Package Validator, Intent Auditor, Security Challenger, Coherence Checker) challenge the output from independent angles.

Triggers: AI-generated code, diffs, files, or Spectra session output needing verification before acceptance.

### coherence-monitor
**Metacognitive audit for long-running work.** Use at checkpoints during complex agent tasks or to audit a completed Spectra session before acting on its recommendation. Answers: "Am I still solving the right problem?"

Triggers: long-running agent checkpoints, mid-session drift detection, auditing completed Spectra sessions.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/dnhess/spectra/main/install.sh | bash
```

This downloads the latest release to `~/.spectra/`, creates symlinks in
`~/.claude/skills/`, and configures permissions automatically.

### Developer setup

For contributors working on Spectra itself:

```bash
git clone https://github.com/dnhess/spectra.git
cd spectra
npm install && npm run prepare
spectra link .
```

### Management

```bash
spectra status      # Show installation info
spectra update      # Update to latest release
spectra doctor      # Diagnose issues
spectra uninstall   # Remove Spectra
```

### Recommended permissions

The installer configures these automatically. Manual setup is only needed
for development from source. Add to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir -p ~/.spectra/sessions/*)",
      "Bash(bash ~/.spectra/bin/json-write.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/db-utils.sh *)",
      "Write(~/.spectra/sessions/**)",
      "Read(~/.spectra/sessions/**)",
      "Glob(~/.spectra/sessions/**)",
      "Write(~/.spectra/.active-*)"
    ]
  }
}
```

These are scoped to session directories only — they don't affect permissions on your codebase.

## Architecture

All skills use the **blackboard architecture** for multi-agent coordination:

```
Agents ──(Write JSON file)──► Session Directory ◄──(Glob/Read)── Moderator
```

- **Agents** write structured JSON files to session subdirectories
- **Moderator** (main Claude instance) polls for files, reads results, writes the JSONL event log
- **No SendMessage** for data exchange — files are the communication medium
- **No coordinator agent** — the moderator drives the session directly

This replaces the previous hub-and-spoke coordinator pattern, eliminating message delivery failures and coordinator stalling.

Additional infrastructure:

- **Scout agent** — every skill runs a pre-session Scout subagent (Phase 2.5) that writes `context-brief.json` to the session directory. Main agents read this file for project/subject context instead of re-gathering it independently, saving tokens at scale.
- **Output validation** — 5-stage pipeline (size, JSON parse, schema, content sanitize, accept) validates all agent output before event log writes
- **SQLite storage** (scaffolded, not yet wired) — hybrid storage layer alongside JSONL manifests for cross-session metadata queries. Schema, utilities, and tests exist but sessions do not yet populate the database. JSONL manifests are the active storage layer.
- **Context budget monitoring** — proxy metrics tracked at every phase transition with emergency shutdown when context pressure is critical
- **Quality KPIs** — per-session metrics (completion rate, convergence, specialist utilization, etc.) computed at session end (SQLite population pending)
- **Skill composition** — skills can invoke other skills mid-session (e.g., deep-design invokes decision-board to resolve a deadlocked topic)
- **Round summarization** — moderator produces condensed ~1000-token round briefs between discussion rounds, replacing raw position injection and reducing token growth from O(agents^2 x rounds^2) to O(agents x rounds)
- **Tier-based model allocation** — each skill defines per-tier model tables (opus for analysis-heavy opening phases, sonnet for discussion/synthesis)

## Context Persistence

Sessions leave a trail for future sessions to build on:

- **Checkpoints** — `session-state.md` written at each phase transition.
  Enables recovery after Claude Code context compaction mid-session.
- **Handoffs** — `handoff.md` written at session end with key findings,
  unresolved items, and follow-up recommendations.
- **Prior Context** — At session start, the moderator queries the manifest
  for prior sessions on the same project and loads the most recent handoff.
  Agents receive unresolved items so they don't repeat resolved findings.

All persistence files use atomic writes (temp-then-rename) and content
sanitization before injection into agent prompts.
See `shared/orchestration.md` for the full protocol.

## Repository Structure

```
spectra/
  bin/
    spectra                     # CLI script
    json-write.sh               # Scoped JSON writer
  README.md                     # This file
  install.sh                    # Curl-based installer
  shared/                       # Shared orchestration library (not a skill)
    orchestration.md            # Blackboard protocol, polling, session management
    event-schemas-base.md       # Common event types across all skills
    composition.md              # Skill composition protocol (inter-skill invocation)
    security.md                 # 4-layer defense, content isolation, audits
    verification.md             # Lightweight 2-agent post-synthesis trust hook
    tools/
      jsonl-utils.sh            # JSONL query utility
      db-utils.sh               # SQLite database utilities (WAL mode)
      validate-output.sh        # 5-stage output validation pipeline
    schemas/                    # JSON validation schemas for agent outputs
  deep-design/                  # Design review skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 12 core + 10 specialist reviewers
  decision-board/               # Decision debate skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 7 core + 9 specialist debaters
  peer-review/                  # Code review skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 6 core + 6 specialist reviewers
  trust-layer/                  # Adversarial verification skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 4 core verification personas
  coherence-monitor/            # Metacognitive audit skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 4 core audit personas
```

## Adding New Skills

To add a new multi-agent skill:

1. Create a directory at the repo root (e.g., `my-skill/`)
2. Add a `SKILL.md` that references `~/.claude/skills/shared/orchestration.md` for the blackboard protocol
3. Add an `event-schemas.md` with domain-specific events, referencing `shared/event-schemas-base.md` for common types
4. Add a `personas/` directory with agent persona files
5. **Wire persistence** — reference the Persistence Protocol in `shared/orchestration.md`:
   - Define your sentinel name (`.active-{skill-name}-session`)
   - Define handoff content mapping for your domain
   - Define which manifest field identifies repeat sessions
   - Add checkpoint timing appropriate for your session phases
6. **Add a Scout phase** — add a Phase 2.5 section between Team Setup and the Opening Round.
   Define skill-specific gather instructions and a `skill_context` schema.
   See `shared/orchestration.md > Scout Agent` for the template.
7. Add the skill name to `KNOWN_SKILLS` in `bin/spectra`

The shared infrastructure handles: session directory management, Scout context-gathering, polling protocol, JSONL event writing, output validation, synthesis pipeline, fault tolerance, context budget monitoring, quality KPIs, security, and context persistence.
