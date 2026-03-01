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
git clone https://github.com/dnhess/spectra.git
cd spectra
./install.sh
```

This creates symlinks in `~/.claude/skills/` pointing to this repository:

- `~/.claude/skills/shared/` → shared orchestration library
- `~/.claude/skills/deep-design/` → design review skill
- `~/.claude/skills/decision-board/` → decision debate skill

### Recommended permissions

Add these to `~/.claude/settings.json` so skill sessions run without manual approval prompts:

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir -p ~/.claude/deep-design-sessions/*)",
      "Bash(mkdir -p ~/.claude/decision-board-sessions/*)",
      "Bash(python3 -c *)",
      "Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)",
      "Write(~/.claude/deep-design-sessions/**)",
      "Write(~/.claude/decision-board-sessions/**)",
      "Read(~/.claude/deep-design-sessions/**)",
      "Read(~/.claude/decision-board-sessions/**)",
      "Glob(~/.claude/deep-design-sessions/**)",
      "Glob(~/.claude/decision-board-sessions/**)",
      "Write(~/.claude/.active-deep-design-session)",
      "Write(~/.claude/.active-decision-board-session)"
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
5. **Wire persistence** — reference the Persistence Protocol in `shared/orchestration.md`:
   - Define your sentinel name (`.active-{skill-name}-session`)
   - Define handoff content mapping for your domain
   - Define which manifest field identifies repeat sessions
   - Add checkpoint timing appropriate for your session phases
6. Add a symlink line to `install.sh`

The shared infrastructure handles: session directory management, polling protocol, JSONL event writing, synthesis pipeline, fault tolerance, security, and context persistence.
