# Spectra CLI & Installer Design

**Date:** 2026-03-01
**Status:** Approved

## Problem

Installing Spectra currently requires cloning the repo and running
`install.sh`. Users must also manually copy permission entries into
`~/.claude/settings.json`. There is no update, uninstall, or
diagnostic tooling. Spectra writes directly into `~/.claude/`,
mixing its files with Claude Code's own data.

## Goals

1. One-command install: `curl -fsSL <url> | bash`
2. Full separation: Spectra owns `~/.spectra/`, only symlinks into
   `~/.claude/skills/`
3. Safe config management: backup before every `settings.json` write,
   restore command if something breaks
4. Developer workflow: `spectra link` for local development without
   cutting releases
5. Self-service CLI: install, update, uninstall, status, doctor,
   backup/restore

## Approach

**GitHub Release Tarball.** The curl installer downloads a tarball from
the latest GitHub release, extracts to `~/.spectra/`, and installs a
CLI script. No git dependency for end users. Developers use
`spectra link` to point at their local checkout.

---

## Directory Layout

```
~/.spectra/
  bin/
    spectra                       # CLI script
  skills/
    shared/                       # orchestration.md, event-schemas-base.md, etc.
    deep-design/                  # SKILL.md, personas/, event-schemas.md
    decision-board/               # SKILL.md, personas/, event-schemas.md
  sessions/
    deep-design/                  # session data (moved from ~/.claude/)
    decision-board/               # session data (moved from ~/.claude/)
  backups/
    settings.json.<timestamp>     # timestamped settings.json backups
  version                         # installed version (e.g., "0.2.0")
  mode                            # "release" or "dev"
  dev-repo                        # path to linked repo (dev mode only)

~/.claude/skills/
  shared -> ~/.spectra/skills/shared
  deep-design -> ~/.spectra/skills/deep-design
  decision-board -> ~/.spectra/skills/decision-board
```

- `~/.spectra/` is the single source of truth for everything Spectra owns
- `~/.claude/skills/` contains only symlinks
- Session data moves from `~/.claude/{skill}-sessions/` to
  `~/.spectra/sessions/{skill}/`
- Backups are timestamped; multiple coexist for safe rollback

## CLI Commands

### spectra install

Called by the curl one-liner. Full install flow:

1. **Pre-flight checks**
   - Bash version >= 3.2 (macOS default)
   - `curl` available
   - `python3` available (warn if missing, do not block)
   - If `~/.spectra/` exists: print "already installed, use
     `spectra update`" and exit

2. **Download**
   - Fetch latest release tag from GitHub API
   - Download tarball for that release
   - Verify download succeeded (exit code + file size > 0)

3. **Extract and place**
   - `mkdir -p ~/.spectra/{skills,sessions,backups,bin}`
   - Extract tarball into `~/.spectra/skills/`
   - Place CLI script into `~/.spectra/bin/spectra`
   - `chmod +x ~/.spectra/bin/spectra`
   - Write version to `~/.spectra/version`
   - Write "release" to `~/.spectra/mode`

4. **Symlink into Claude**
   - `mkdir -p ~/.claude/skills`
   - `ln -sfn` for each skill directory

5. **Configure permissions**
   - Backup `~/.claude/settings.json` to
     `~/.spectra/backups/settings.json.<timestamp>`
   - Parse existing settings.json (or create default `{}` if missing)
   - Merge Spectra permission entries (idempotent: skip if present)
   - Write to temp file, validate JSON, atomic `mv`
   - Print diff of what changed

6. **Add CLI to PATH**
   - Symlink `~/.spectra/bin/spectra` to `~/.local/bin/spectra`
   - If `~/.local/bin` not in PATH: print instructions to add it

7. **Summary**
   - Print installed version, installed skills, any warnings

### spectra update

1. Check current version from `~/.spectra/version`
2. If mode is "dev": print warning, suggest `git pull` or
   `spectra unlink` first, exit
3. Fetch latest release tag from GitHub API
4. Compare; if same: print "already up to date", exit
5. Download new tarball
6. Replace `~/.spectra/skills/` (remove + extract)
   - `sessions/` and `backups/` are NEVER touched
7. Replace `~/.spectra/bin/spectra` with new CLI
8. Re-check symlinks (repair if broken)
9. Re-merge permissions (backup first, handles new skills)
10. Update `~/.spectra/version`
11. Print what changed

### spectra uninstall

1. Backup `settings.json` (safety first, even on uninstall)
2. Remove Spectra permission entries from `settings.json`
   (same parse/merge/validate/atomic-write protocol)
3. Remove symlinks from `~/.claude/skills/` — only those pointing
   into `~/.spectra/`
4. Prompt: "Delete session data? (y/N)"
   - Default No: preserves `~/.spectra/sessions/`
   - If No: move sessions to `~/.spectra-sessions-backup/`
   - If Yes: remove sessions
5. Remove `~/.spectra/bin/spectra` and `~/.local/bin/spectra` symlink
6. Remove `~/.spectra/`
7. Print confirmation

### spectra link \<path\>

Switch to dev mode — symlink skills to a local repo checkout:

1. Verify `<path>` is a Spectra repo (check for `shared/`,
   `install.sh`)
2. Write "dev" to `~/.spectra/mode`
3. Write repo path to `~/.spectra/dev-repo`
4. Remove downloaded files from `~/.spectra/skills/`
5. Create symlinks: `~/.spectra/skills/shared` →
   `<path>/shared`, etc.
6. Chain: `~/.claude/skills/shared` → `~/.spectra/skills/shared` →
   `<path>/shared`

### spectra unlink

Revert to release mode:

1. Remove symlinks from `~/.spectra/skills/`
2. Re-download latest release tarball
3. Extract into `~/.spectra/skills/`
4. Write "release" to `~/.spectra/mode`
5. Remove `~/.spectra/dev-repo`

### spectra status

Display:

- Installed version and latest available version
- Mode: `release (v0.2.0)` or `dev (linked to ~/Projects/spectra)`
- Installed skills (list directories in `~/.spectra/skills/`)
- Symlink health (all intact or broken)
- Session data size per skill
- Whether permissions are configured in `settings.json`

### spectra doctor

Diagnose and suggest fixes:

- Dependencies present (python3, bash, curl)
- Symlinks intact and pointing to valid targets
- Permissions in `settings.json` match expected set
- Session directories writable
- No stale/orphaned files
- If old-path sessions exist in `~/.claude/{skill}-sessions/`:
  offer migration command
- Dev mode: linked repo path still exists

### spectra backup list

List all `~/.spectra/backups/settings.json.*` with timestamps,
most recent first.

### spectra backup restore \[timestamp\]

1. If no timestamp: use most recent backup
2. Verify backup file exists and is valid JSON
3. Backup current `settings.json` (yes, backup before restoring)
4. Copy backup to `~/.claude/settings.json`
5. Print confirmation with diff

## Settings.json Safety Protocol

Every mutation to `~/.claude/settings.json` follows this protocol:

1. Create timestamped backup in `~/.spectra/backups/`
2. Read existing JSON with `python3 -c 'import json; ...'`
3. Merge only Spectra-specific permission entries (never touch
   other keys)
4. Write to temp file first
5. Validate temp file parses as valid JSON
6. Atomic `mv` temp file to `settings.json`
7. If validation fails: auto-restore from backup, print error

This applies to install, update, uninstall, and restore operations.

## Permission Entries

Consolidated permissions merged into `settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir -p ~/.spectra/sessions/*)",
      "Bash(python3 -c *)",
      "Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)",
      "Write(~/.spectra/sessions/**)",
      "Read(~/.spectra/sessions/**)",
      "Glob(~/.spectra/sessions/**)",
      "Write(~/.spectra/.active-*)"
    ]
  }
}
```

Changes from current:

- Session permissions point to `~/.spectra/sessions/` instead of
  `~/.claude/{skill}-sessions/`
- One rule per operation covers all skills (no per-skill duplication)
- Sentinel files move to `~/.spectra/.active-*`

## SKILL.md Path Migration

Paths updated in skill files and `shared/orchestration.md`:

| Old path | New path |
|---|---|
| `~/.claude/{skill}-sessions/` | `~/.spectra/sessions/{skill}/` |
| `~/.claude/.active-{skill}-session` | `~/.spectra/.active-{skill}-session` |

Skill references to shared infrastructure stay as
`~/.claude/skills/shared/...` (symlinks handle indirection).

## Existing User Migration

The installer does NOT auto-migrate existing session data from
`~/.claude/{skill}-sessions/`. `spectra doctor` detects orphaned
old-path sessions and prints a command to move them.

## Release Automation

### .github/workflows/release.yml

Trigger: push a git tag matching `v*.*.*`

1. Run lint checks (markdown, shellcheck, commitlint)
2. Build tarball:
   - Include: `shared/`, `deep-design/`, `decision-board/`,
     any other skill dirs, `bin/spectra`
   - Exclude: `node_modules/`, `.git/`, `.github/`, `docs/`
   - Name: `spectra-v{version}.tar.gz`
3. Create GitHub release with:
   - Tag name as title
   - Auto-generated changelog
   - Tarball attached as release asset

### Repo structure after implementation

```
spectra/
  bin/
    spectra                    # CLI script (new)
  install.sh                   # Curl entry point (rewritten)
  shared/                      # (unchanged)
  deep-design/                 # (unchanged)
  decision-board/              # (unchanged)
  .github/workflows/
    lint.yml                   # (unchanged)
    release.yml                # (new)
```

## Dependencies

The installer checks for and warns about:

- `bash` >= 3.2
- `curl`
- `python3` (used for JSON manipulation and by skills at runtime)

No dependencies are auto-installed. Warnings include instructions
for how to install missing tools on macOS and common Linux distros.
