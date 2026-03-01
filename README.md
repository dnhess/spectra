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

## Installation

```bash
./install.sh
```

This creates symlinks in `~/.claude/skills/` pointing to this repository:
- `~/.claude/skills/shared/` → shared orchestration library
- `~/.claude/skills/deep-design/` → design review skill
- `~/.claude/skills/decision-board/` → decision debate skill

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

## Repository Structure

```
spectra/
  README.md                     # This file
  install.sh                    # Symlink installer
  shared/                       # Shared orchestration library (not a skill)
    orchestration.md            # Blackboard protocol, polling, session management
    event-schemas-base.md       # Common event types across all skills
    security.md                 # 3-layer defense, content isolation, audits
    tools/
      jsonl-utils.sh            # JSONL query utility
  deep-design/                  # Design review skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 10 core + 8 specialist reviewers
  decision-board/               # Decision debate skill
    SKILL.md                    # Domain orchestration
    event-schemas.md            # Domain-specific event types
    personas/                   # 6 core + 6 specialist debaters
```

## Adding New Skills

To add a new multi-agent skill:

1. Create a directory at the repo root (e.g., `my-skill/`)
2. Add a `SKILL.md` that references `~/.claude/skills/shared/orchestration.md` for the blackboard protocol
3. Add an `event-schemas.md` with domain-specific events, referencing `shared/event-schemas-base.md` for common types
4. Add a `personas/` directory with agent persona files
5. Add a symlink line to `install.sh`

The shared infrastructure handles: session directory management, polling protocol, JSONL event writing, synthesis pipeline, fault tolerance, and security.
