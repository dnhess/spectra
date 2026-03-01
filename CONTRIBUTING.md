# Contributing to Spectra

Thanks for your interest in contributing. This guide covers how to add skills, modify existing ones, and submit changes.

## Getting Started

1. Fork the repository
2. Clone your fork and set up local tooling:

   ```bash
   git clone https://github.com/YOUR_USERNAME/spectra.git
   cd spectra
   npm install       # installs commitlint, markdownlint, husky
   npm run prepare   # activates git hooks
   ./install.sh      # symlinks skills into ~/.claude/skills/
   ```

3. Create a branch for your changes: `git checkout -b feat/my-change`

This installs pre-commit hooks that validate your commits locally before you push. If you skip this step, CI will still catch violations on the PR.

## Skill File Format

Each skill lives in its own directory and must contain:

- **`SKILL.md`** — The full orchestration specification. References `shared/orchestration.md` for the blackboard protocol.
- **`event-schemas.md`** — Domain-specific event types. References `shared/event-schemas-base.md` for common types. Never duplicate common events.
- **`personas/`** — Markdown files defining agent personas (core personas at root, specialists in `personas/specialists/`).

### Key conventions

- Agent output files are always JSON, serialized with `python3 -c 'import json; ...'` — never string concatenation
- The moderator (main Claude instance) is the sole JSONL event log writer
- Agents communicate by writing files to session subdirectories, not via SendMessage
- Session directories live under `~/.claude/{skill-name}-sessions/`

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new adversarial-review skill
fix: correct install script path resolution
docs: improve README quick start section
chore: update .gitignore
```

## Pull Request Process

1. Ensure your skill files follow the established format
2. Test with Claude Code if modifying orchestration logic
3. Update `CHANGELOG.md` under `[Unreleased]` if adding or changing skills
4. Update `install.sh` if adding a new skill directory
5. Submit your PR with a clear description of what changed and why

## Adding a New Skill

1. Create a directory at the repo root (e.g., `my-skill/`)
2. Add `SKILL.md` referencing `~/.claude/skills/shared/orchestration.md`
3. Add `event-schemas.md` with domain-specific events, referencing `shared/event-schemas-base.md`
4. Add `personas/` with agent persona files
5. Add a symlink line to `install.sh`
6. Update `README.md` to list the new skill

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.
