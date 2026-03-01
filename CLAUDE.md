# Spectra

Multi-agent orchestration skills using a blackboard architecture. All agent coordination is file-based — agents write JSON files, the moderator polls and reads them.

## Structure

- `shared/` — Reusable orchestration infrastructure (not a skill itself)
  - `orchestration.md` — Blackboard protocol, polling, session management
  - `event-schemas-base.md` — Common event types (session_start, phase_transition, agent_complete, session_complete, session_end, feedback, security_violation, composition_invoked, composition_completed)
  - `composition.md` — Skill composition protocol for inter-skill invocation mid-session
  - `security.md` — 3-layer defense model, content isolation, directory audits
  - `tools/jsonl-utils.sh` — JSONL query utility (single copy, used by all skills)
- `deep-design/` — Multi-perspective design review skill (v4.0)
  - `SKILL.md` — Full orchestration spec, references `shared/`
  - `event-schemas.md` — Domain events only (review, rebuttal, topic_created, etc.)
  - `personas/` — 10 core + 8 specialist reviewer personas
- `decision-board/` — Structured decision debate skill (v2.0)
  - `SKILL.md` — Full orchestration spec, references `shared/`
  - `event-schemas.md` — Domain events only (stance, challenge, concession, etc.)
  - `personas/` — 6 core + 6 specialist debater personas

## Key Architecture Decisions

- **Blackboard, not hub-and-spoke**: No coordinator agent. The moderator (main Claude instance) drives sessions directly. Agents write files to session subdirectories; moderator polls with Glob.
- **Single JSONL writer**: Only the moderator writes to the event log. No writer handoff, no write ordering violations.
- **Fresh agents per round**: Discussion/debate rounds spawn new agents rather than reusing previous ones. More expensive but guarantees delivery (avoids SendMessage failures).
- **No cost tracking**: Platform doesn't expose token counts. Budget ceiling and cost snapshots were removed as non-functional.
- **No heartbeat monitoring**: No timer mechanism in Claude Code. Replaced by file-existence polling with timeouts.

## Conventions

- All agents use `general-purpose` subagent type with `bypassPermissions` mode (needed for file writes). Security is enforced via prompt-level path constraints and post-phase directory audits.
- Agent output files are always JSON, serialized with `python3 -c 'import json; ...'` — never string concatenation.
- Session directories live under `~/.claude/{skill-name}-sessions/`.
- Persona files are plain markdown in `personas/` (core) and `personas/specialists/` (domain specialists).
- Domain event schemas reference `shared/event-schemas-base.md` for common types — never duplicate them.

## Editing Guidelines

- When modifying orchestration behavior, update `shared/orchestration.md` — both skills inherit from it.
- When adding domain-specific events, add to the skill's own `event-schemas.md`, not to the shared base.
- Never add coordinator, heartbeat, or cost tracking patterns — these were intentionally removed.
- Persona files are independent of the orchestration layer. Edit freely without touching SKILL.md.
- `install.sh` creates symlinks into `~/.claude/skills/`. Update it when adding new skills.

## Enforced Standards

These are not suggestions — CI will block merge if violated:

- **Conventional commits required.** Every commit must follow `type: description` format. Valid types: `feat`, `fix`, `docs`, `chore`, `refactor`, `style`, `ci`, `test`. Enforced by commitlint in CI and pre-commit hook.
- **Markdown lint must pass.** Config in `.markdownlint.yml`. Run locally: `npm run lint`
- **ShellCheck must pass** on all `.sh` files.
- **CHANGELOG.md is auto-generated** by release-please. Do not edit it manually. Write meaningful conventional commit messages instead — they become the changelog.
- **CODEOWNERS review required** for changes to `shared/`, `install.sh`, `SKILL.md`, or `event-schemas.md`.
- **All PRs require approval** before merge. No direct pushes to main.

### Local setup for hooks

```bash
npm install    # installs husky, commitlint, markdownlint-cli2
npm run prepare # sets up git hooks
```

After this, commits are validated locally before push.
