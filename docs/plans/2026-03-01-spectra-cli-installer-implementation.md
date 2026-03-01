# Spectra CLI & Installer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the `spectra` CLI, rewrite `install.sh` as a curl-based installer, add release automation, migrate all session paths from `~/.claude/` to `~/.spectra/`, and replace the broad `python3 -c *` permission with a scoped `json-write.sh` wrapper.

**Architecture:** A single Bash CLI script (`bin/spectra`) dispatches subcommands (install, update, rollback, uninstall, link, unlink, status, doctor, backup). Shared utility functions (atomic swap, mkdir-based locking, checksum verification, settings.json merge) live in the same file. `install.sh` is rewritten as a curl-pipe-bash entry point that delegates to `spectra install`. A GitHub Actions release workflow builds tarballs with SHA-256 checksums.

**Tech Stack:** Bash (>=3.2), GitHub Actions, ShellCheck, python3 (for JSON manipulation only via `json-write.sh`)

**Design doc:** `docs/plans/2026-03-01-spectra-cli-installer-design.md`
**Revised design (post-review):** `~/.claude/deep-design-sessions/cli-installer-20260301T170517/revised-document.md`
**Branch:** `feat/spectra-cli-installer` (created from `main`)

---

## Task 1: Create `bin/json-write.sh` — scoped JSON writer

**Files:**
- Create: `bin/json-write.sh`

This replaces the broad `Bash(python3 -c *)` permission. It reads JSON from stdin
or a string argument, validates it, and writes atomically to a specified path.
Path-constrained to `~/.spectra/sessions/` only.

**Step 1: Write `bin/json-write.sh`**

```bash
#!/bin/bash
# json-write.sh — scoped JSON writer for Spectra agent output
# Usage: json-write.sh <output-path> [json-string]
# If json-string omitted, reads from stdin.
# Path constraint: only writes under ~/.spectra/sessions/ or the
# session directory passed via SPECTRA_SESSION_DIR env var.
set -euo pipefail

die() { echo "json-write: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: json-write.sh <output-path> [json-string]"

output_path="$1"
shift

# Read JSON from argument or stdin
if [[ $# -ge 1 ]]; then
  json_data="$1"
else
  json_data="$(cat)"
fi

# Resolve to absolute path
abs_path="$(cd "$(dirname "$output_path")" 2>/dev/null && pwd)/$(basename "$output_path")" \
  || die "parent directory does not exist: $(dirname "$output_path")"

# Path constraint: must be under allowed directories
allowed=false
sessions_dir="$HOME/.spectra/sessions"
if [[ "$abs_path" == "$sessions_dir"/* ]]; then
  allowed=true
fi
# Also allow SPECTRA_SESSION_DIR if set (for deep-design-sessions etc.)
if [[ -n "${SPECTRA_SESSION_DIR:-}" ]] && [[ "$abs_path" == "${SPECTRA_SESSION_DIR}"/* ]]; then
  allowed=true
fi
# Allow ~/.claude/*-sessions/ for backward compatibility
if [[ "$abs_path" == "$HOME/.claude/"*"-sessions/"* ]]; then
  allowed=true
fi

[[ "$allowed" == "true" ]] || die "path not allowed: $output_path (must be under $sessions_dir)"

# Validate JSON
echo "$json_data" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null \
  || die "invalid JSON"

# Atomic write: temp file then mv
tmp_file="${abs_path}.tmp.$$"
echo "$json_data" > "$tmp_file"
mv "$tmp_file" "$abs_path"
```

**Step 2: Make executable and run ShellCheck**

Run: `chmod +x bin/json-write.sh && npx shellcheck bin/json-write.sh`
Expected: PASS (no errors)

**Step 3: Commit**

```bash
git add bin/json-write.sh
git commit -m "feat: add json-write.sh scoped JSON writer

Replaces broad Bash(python3 -c *) permission with a path-constrained
wrapper that validates JSON before atomic write."
```

---

## Task 2: Create `bin/spectra` — CLI skeleton with shared utility functions

**Files:**
- Create: `bin/spectra`

This task creates the CLI entry point with argument dispatch and all shared
utility functions. Commands are stubbed — each is implemented in subsequent tasks.

**Step 1: Write `bin/spectra`**

```bash
#!/bin/bash
# spectra — Spectra CLI for managing multi-agent skills
set -euo pipefail

readonly SPECTRA_VERSION="0.2.0"
readonly SPECTRA_HOME="$HOME/.spectra"
readonly CLAUDE_HOME="$HOME/.claude"
readonly SKILLS_DIR="$SPECTRA_HOME/skills"
readonly SESSIONS_DIR="$SPECTRA_HOME/sessions"
readonly BACKUPS_DIR="$SPECTRA_HOME/backups"
readonly BIN_DIR="$SPECTRA_HOME/bin"
readonly CLAUDE_SKILLS_DIR="$CLAUDE_HOME/skills"
readonly VERSION_FILE="$SPECTRA_HOME/version"
readonly MODE_FILE="$SPECTRA_HOME/mode"
readonly LOCK_DIR="$SPECTRA_HOME/.settings-lock"
readonly GITHUB_REPO="dnhess/spectra"

# Known skills (update when adding new skills)
readonly KNOWN_SKILLS=(shared deep-design decision-board code-review)

# --- Logging ---

log_info() { echo "  $*"; }
log_success() { echo "  ✓ $*"; }
log_warn() { echo "  ! $*" >&2; }
log_error() { echo "  ✗ $*" >&2; }
log_header() { echo ""; echo "=== $* ==="; echo ""; }

# --- Prerequisite checks ---

require_installed() {
  [[ -d "$SPECTRA_HOME" ]] || { log_error "Spectra is not installed. Run: curl -fsSL <url> | bash"; exit 1; }
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Required command not found: $1"; exit 1; }
}

detect_checksum_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    log_error "No SHA-256 tool found. Install coreutils."
    exit 1
  fi
}

# --- GitHub API helpers ---

fetch_latest_release() {
  local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
  curl -fsSL "$api_url" 2>/dev/null || { log_error "Failed to fetch release info from GitHub"; exit 1; }
}

get_release_tag() {
  local release_json="$1"
  echo "$release_json" | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])"
}

get_release_asset_url() {
  local release_json="$1"
  local asset_name="$2"
  echo "$release_json" | python3 -c "
import sys, json
release = json.load(sys.stdin)
for asset in release.get('assets', []):
    if asset['name'] == '$asset_name':
        print(asset['browser_download_url'])
        sys.exit(0)
print('', end='')
sys.exit(1)
"
}

# --- Checksum verification ---

verify_checksum() {
  local tarball="$1"
  local checksums_file="$2"
  local checksum_cmd
  checksum_cmd="$(detect_checksum_cmd)"

  local expected actual tarball_name
  tarball_name="$(basename "$tarball")"
  expected="$(grep "$tarball_name" "$checksums_file" | awk '{print $1}')"
  actual="$($checksum_cmd "$tarball" | awk '{print $1}')"

  if [[ "$expected" != "$actual" ]]; then
    log_error "Checksum mismatch!"
    log_error "  Expected: $expected"
    log_error "  Actual:   $actual"
    exit 1
  fi
  log_success "Checksum verified"
}

# --- Atomic swap ---

atomic_swap() {
  local target="$1"
  local staging="$2"
  local backup="$3"

  # shellcheck disable=SC2064
  trap "if [ -d '$backup' ] && [ ! -d '$target' ]; then mv '$backup' '$target'; fi; rm -rf '$staging'" EXIT INT TERM

  if [[ -d "$target" ]]; then
    mv "$target" "$backup"
  fi
  mv "$staging" "$target"

  # Reset trap after success
  trap - EXIT INT TERM
}

# --- Settings.json locking ---

acquire_lock() {
  local max_wait=5
  local elapsed=0

  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # Check for stale lock
    if [[ -f "$LOCK_DIR/pid" ]]; then
      local lock_pid
      lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")"
      if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        log_warn "Removing stale lock (PID $lock_pid is dead)"
        rm -rf "$LOCK_DIR"
        continue
      fi
    fi

    # Check lock age (stale if > 5 minutes)
    if [[ -d "$LOCK_DIR" ]]; then
      local lock_age
      lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "0") ))
      if [[ "$lock_age" -gt 300 ]]; then
        log_warn "Removing stale lock (older than 5 minutes)"
        rm -rf "$LOCK_DIR"
        continue
      fi
    fi

    sleep 0.2
    elapsed=$((elapsed + 1))
    if [[ "$elapsed" -ge $((max_wait * 5)) ]]; then
      log_error "Could not acquire settings lock after ${max_wait}s"
      log_error "Another spectra operation may be in progress."
      log_error "If not, remove: $LOCK_DIR"
      exit 1
    fi
  done

  echo $$ > "$LOCK_DIR/pid"
  # shellcheck disable=SC2064
  trap "rm -rf '$LOCK_DIR'" EXIT INT TERM
}

release_lock() {
  rm -rf "$LOCK_DIR"
  trap - EXIT INT TERM
}

# --- Settings.json merge ---

settings_backup() {
  local settings_file="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings_file" ]]; then
    mkdir -p "$BACKUPS_DIR"
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    cp "$settings_file" "$BACKUPS_DIR/settings.json.$timestamp"
    log_success "Backed up settings.json ($timestamp)"
  fi
}

get_spectra_permissions() {
  cat <<'PERMS'
["Bash(mkdir -p ~/.spectra/sessions/*)","Bash(bash ~/.spectra/bin/json-write.sh *)","Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)","Write(~/.spectra/sessions/**)","Read(~/.spectra/sessions/**)","Glob(~/.spectra/sessions/**)","Write(~/.spectra/.active-*)"]
PERMS
}

settings_merge_permissions() {
  local settings_file="$CLAUDE_HOME/settings.json"
  local action="${1:-add}"  # "add" or "remove"

  # Record mtime before read (compare-and-swap)
  local mtime_before=""
  if [[ -f "$settings_file" ]]; then
    mtime_before="$(stat -f %m "$settings_file" 2>/dev/null || stat -c %Y "$settings_file" 2>/dev/null)"
  fi

  # Read current settings
  local current="{}"
  if [[ -f "$settings_file" ]]; then
    current="$(cat "$settings_file")"
  fi

  local spectra_perms
  spectra_perms="$(get_spectra_permissions)"

  # Merge or remove permissions
  local updated
  updated="$(echo "$current" | python3 -c "
import sys, json

settings = json.load(sys.stdin)
spectra_perms = json.loads('$spectra_perms')
action = '$action'

perms = settings.get('permissions', {})
allow = perms.get('allow', [])

if action == 'add':
    for p in spectra_perms:
        if p not in allow:
            allow.append(p)
elif action == 'remove':
    allow = [p for p in allow if p not in spectra_perms]

if allow:
    perms['allow'] = allow
    settings['permissions'] = perms
elif 'permissions' in settings and 'allow' in settings['permissions']:
    settings['permissions']['allow'] = allow

json.dump(settings, sys.stdout, indent=2)
print()
")" || { log_error "Failed to merge permissions"; return 1; }

  # Validate JSON
  echo "$updated" | python3 -c "import sys, json; json.load(sys.stdin)" \
    || { log_error "Merged settings.json is invalid JSON"; return 1; }

  # Compare-and-swap: check mtime hasn't changed
  if [[ -f "$settings_file" ]]; then
    local mtime_after
    mtime_after="$(stat -f %m "$settings_file" 2>/dev/null || stat -c %Y "$settings_file" 2>/dev/null)"
    if [[ "$mtime_before" != "$mtime_after" ]]; then
      log_error "settings.json was modified by another process during merge"
      log_error "Re-run the command to retry"
      return 1
    fi
  fi

  # Atomic write
  local tmp_file="$settings_file.tmp.$$"
  echo "$updated" > "$tmp_file"
  mv "$tmp_file" "$settings_file"
}

# --- Symlink helpers ---

create_skill_symlinks() {
  local source_base="$1"  # e.g., ~/.spectra/skills or /path/to/repo
  mkdir -p "$CLAUDE_SKILLS_DIR"
  for skill in "${KNOWN_SKILLS[@]}"; do
    if [[ -d "$source_base/$skill" ]]; then
      ln -sfn "$source_base/$skill" "$CLAUDE_SKILLS_DIR/$skill"
      log_success "Linked $skill"
    fi
  done
}

remove_spectra_symlinks() {
  for skill in "${KNOWN_SKILLS[@]}"; do
    local link="$CLAUDE_SKILLS_DIR/$skill"
    if [[ -L "$link" ]]; then
      local target
      target="$(readlink "$link")"
      if [[ "$target" == "$SPECTRA_HOME"/* ]] || [[ "$target" == *"/spectra/"* ]]; then
        rm "$link"
        log_success "Removed symlink: $skill"
      fi
    fi
  done
}

# --- Commands ---

cmd_install() {
  log_header "Spectra Install"

  # Pre-flight
  if [[ -d "$SPECTRA_HOME" ]]; then
    log_error "Spectra is already installed at $SPECTRA_HOME"
    log_info "Use 'spectra update' to get the latest version"
    exit 1
  fi

  require_command curl
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not found — skills require it at runtime"
  fi
  detect_checksum_cmd >/dev/null

  # Download
  log_info "Fetching latest release..."
  local release_json
  release_json="$(fetch_latest_release)"
  local tag
  tag="$(get_release_tag "$release_json")"
  local version="${tag#v}"
  log_info "Latest version: $version"

  local tarball_name="spectra-${tag}.tar.gz"
  local tarball_url checksums_url
  tarball_url="$(get_release_asset_url "$release_json" "$tarball_name")"
  checksums_url="$(get_release_asset_url "$release_json" "checksums.txt")"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" EXIT

  curl -fsSL -o "$tmp_dir/$tarball_name" "$tarball_url"
  curl -fsSL -o "$tmp_dir/checksums.txt" "$checksums_url"

  # Verify checksum
  verify_checksum "$tmp_dir/$tarball_name" "$tmp_dir/checksums.txt"

  # Extract and place
  mkdir -p "$SPECTRA_HOME"/{skills,sessions,backups,bin}
  tar -xzf "$tmp_dir/$tarball_name" -C "$SPECTRA_HOME/skills/"
  log_success "Extracted skills to $SKILLS_DIR"

  # Install CLI and json-write.sh from tarball bin/
  if [[ -f "$SPECTRA_HOME/skills/bin/spectra" ]]; then
    cp "$SPECTRA_HOME/skills/bin/spectra" "$BIN_DIR/spectra"
    chmod +x "$BIN_DIR/spectra"
  fi
  if [[ -f "$SPECTRA_HOME/skills/bin/json-write.sh" ]]; then
    cp "$SPECTRA_HOME/skills/bin/json-write.sh" "$BIN_DIR/json-write.sh"
    chmod +x "$BIN_DIR/json-write.sh"
  fi
  # Remove bin/ from skills/ (it's a CLI artifact, not a skill)
  rm -rf "$SPECTRA_HOME/skills/bin"

  echo "$version" > "$VERSION_FILE"
  echo "release" > "$MODE_FILE"
  log_success "Installed version $version"

  # Symlinks
  create_skill_symlinks "$SKILLS_DIR"

  # Create session directories
  for skill in deep-design decision-board code-review; do
    mkdir -p "$SESSIONS_DIR/$skill"
  done

  # Migration compatibility symlinks
  for skill in deep-design decision-board code-review; do
    local old_path="$CLAUDE_HOME/${skill}-sessions"
    if [[ ! -e "$old_path" ]]; then
      ln -sfn "$SESSIONS_DIR/$skill" "$old_path"
      log_info "Created compat symlink: ${skill}-sessions"
    fi
  done

  # Configure permissions
  settings_backup
  acquire_lock
  settings_merge_permissions "add" || { release_lock; exit 1; }
  release_lock
  log_success "Permissions configured in settings.json"

  # Add to PATH
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$BIN_DIR/spectra" "$HOME/.local/bin/spectra"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warn "\$HOME/.local/bin is not in your PATH"
    log_info "Add to your shell profile:"
    log_info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  # Summary
  log_header "Install Complete"
  log_info "Version: $version"
  log_info "Skills:  ${KNOWN_SKILLS[*]}"
  log_info "Home:    $SPECTRA_HOME"

  rm -rf "$tmp_dir"
  trap - EXIT
}

cmd_update() {
  require_installed
  log_header "Spectra Update"

  local current_mode
  current_mode="$(cat "$MODE_FILE" 2>/dev/null || echo "release")"
  if [[ "$current_mode" == "dev" ]]; then
    local repo_path
    repo_path="$(cat "$SPECTRA_HOME/dev-repo" 2>/dev/null || echo "unknown")"
    log_error "Spectra is in dev mode (linked to $repo_path)"
    log_info "Run 'spectra unlink' first, or use 'git pull' in your repo"
    exit 1
  fi

  local current_version
  current_version="$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")"
  log_info "Current version: $current_version"

  log_info "Fetching latest release..."
  local release_json
  release_json="$(fetch_latest_release)"
  local tag
  tag="$(get_release_tag "$release_json")"
  local version="${tag#v}"

  if [[ "$current_version" == "$version" ]]; then
    log_success "Already up to date ($version)"
    exit 0
  fi
  log_info "New version available: $version"

  # Download
  local tarball_name="spectra-${tag}.tar.gz"
  local tarball_url checksums_url
  tarball_url="$(get_release_asset_url "$release_json" "$tarball_name")"
  checksums_url="$(get_release_asset_url "$release_json" "checksums.txt")"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" EXIT

  curl -fsSL -o "$tmp_dir/$tarball_name" "$tarball_url"
  curl -fsSL -o "$tmp_dir/checksums.txt" "$checksums_url"
  verify_checksum "$tmp_dir/$tarball_name" "$tmp_dir/checksums.txt"

  # Extract to staging
  local staging_dir="$SPECTRA_HOME/skills-staging"
  mkdir -p "$staging_dir"
  tar -xzf "$tmp_dir/$tarball_name" -C "$staging_dir/"

  # Update bin/ from staging
  if [[ -f "$staging_dir/bin/spectra" ]]; then
    cp "$staging_dir/bin/spectra" "$BIN_DIR/spectra"
    chmod +x "$BIN_DIR/spectra"
  fi
  if [[ -f "$staging_dir/bin/json-write.sh" ]]; then
    cp "$staging_dir/bin/json-write.sh" "$BIN_DIR/json-write.sh"
    chmod +x "$BIN_DIR/json-write.sh"
  fi
  rm -rf "$staging_dir/bin"

  # Atomic swap
  atomic_swap "$SKILLS_DIR" "$staging_dir" "$SPECTRA_HOME/skills-prev"
  log_success "Skills updated (previous version preserved for rollback)"

  # Re-check symlinks
  create_skill_symlinks "$SKILLS_DIR"

  # Re-merge permissions
  settings_backup
  acquire_lock
  settings_merge_permissions "add" || { release_lock; exit 1; }
  release_lock

  echo "$version" > "$VERSION_FILE"
  log_header "Update Complete"
  log_info "Updated: $current_version → $version"
  log_info "Run 'spectra rollback' to revert if needed"

  rm -rf "$tmp_dir"
  trap - EXIT
}

cmd_rollback() {
  require_installed
  log_header "Spectra Rollback"

  local prev_dir="$SPECTRA_HOME/skills-prev"
  if [[ ! -d "$prev_dir" ]]; then
    log_error "No previous version available for rollback"
    exit 1
  fi

  # Swap current and previous
  local failed_dir="$SPECTRA_HOME/skills-failed"
  mv "$SKILLS_DIR" "$failed_dir"
  mv "$prev_dir" "$SKILLS_DIR"
  mv "$failed_dir" "$prev_dir"

  # Refresh symlinks
  create_skill_symlinks "$SKILLS_DIR"

  # Read version from rolled-back skills (if version marker exists)
  log_success "Rolled back successfully"
  log_info "Run 'spectra rollback' again to swap back"
}

cmd_uninstall() {
  require_installed
  log_header "Spectra Uninstall"

  # Backup and remove permissions
  settings_backup
  acquire_lock
  settings_merge_permissions "remove" || log_warn "Failed to clean permissions"
  release_lock

  # Remove skill symlinks
  remove_spectra_symlinks

  # Remove compat symlinks
  for skill in deep-design decision-board code-review; do
    local compat="$CLAUDE_HOME/${skill}-sessions"
    if [[ -L "$compat" ]]; then
      local target
      target="$(readlink "$compat")"
      if [[ "$target" == "$SESSIONS_DIR"/* ]]; then
        rm "$compat"
        log_success "Removed compat symlink: ${skill}-sessions"
      fi
    fi
  done

  # Session data prompt
  if [[ -d "$SESSIONS_DIR" ]] && [[ "$(ls -A "$SESSIONS_DIR" 2>/dev/null)" ]]; then
    echo ""
    read -rp "  Delete session data? (y/N) " delete_sessions
    if [[ "${delete_sessions,,}" == "y" ]]; then
      rm -rf "$SESSIONS_DIR"
      log_success "Session data deleted"
    else
      local backup_loc="$HOME/.spectra-sessions-backup"
      mv "$SESSIONS_DIR" "$backup_loc"
      log_success "Session data preserved at $backup_loc"
    fi
  fi

  # Remove PATH symlink
  rm -f "$HOME/.local/bin/spectra"

  # Remove spectra home
  rm -rf "$SPECTRA_HOME"
  log_header "Uninstall Complete"
  log_info "Spectra has been removed"
  log_info "Backups were preserved at ~/.spectra/backups/ (now removed)"
}

cmd_link() {
  require_installed
  local repo_path="${1:-}"

  if [[ -z "$repo_path" ]]; then
    log_error "Usage: spectra link <path-to-spectra-repo>"
    exit 1
  fi

  # Resolve to absolute path
  repo_path="$(cd "$repo_path" 2>/dev/null && pwd)" \
    || { log_error "Path does not exist: $1"; exit 1; }

  # Verify it's a Spectra repo
  if [[ ! -d "$repo_path/shared" ]] || [[ ! -f "$repo_path/install.sh" ]]; then
    log_error "Not a Spectra repo: $repo_path"
    log_info "Expected shared/ directory and install.sh"
    exit 1
  fi

  # Check if already linked
  local current_mode
  current_mode="$(cat "$MODE_FILE" 2>/dev/null || echo "release")"
  if [[ "$current_mode" == "dev" ]]; then
    local current_repo
    current_repo="$(cat "$SPECTRA_HOME/dev-repo" 2>/dev/null || echo "")"
    log_error "Already in dev mode (linked to $current_repo)"
    log_info "Run 'spectra unlink' first"
    exit 1
  fi

  log_header "Spectra Link"

  # Save current symlink targets for unlink restoration
  local manifest="$SPECTRA_HOME/dev-link-manifest.json"
  python3 -c "
import json, os
targets = {}
skills_dir = os.path.expanduser('~/.claude/skills')
for skill in ['shared', 'deep-design', 'decision-board', 'code-review']:
    link = os.path.join(skills_dir, skill)
    if os.path.islink(link):
        targets[skill] = os.readlink(link)
json.dump(targets, open('$manifest', 'w'), indent=2)
print()
"
  log_success "Saved current symlink targets"

  # Create direct symlinks to repo
  create_skill_symlinks "$repo_path"

  echo "dev" > "$MODE_FILE"
  echo "$repo_path" > "$SPECTRA_HOME/dev-repo"

  log_header "Dev Mode Active"
  log_info "Linked to: $repo_path"
  log_info "Run 'spectra unlink' to revert to release mode"
}

cmd_unlink() {
  require_installed
  log_header "Spectra Unlink"

  local current_mode
  current_mode="$(cat "$MODE_FILE" 2>/dev/null || echo "release")"
  if [[ "$current_mode" != "dev" ]]; then
    log_error "Not in dev mode"
    exit 1
  fi

  # Remove current symlinks
  remove_spectra_symlinks

  # Restore release symlinks
  create_skill_symlinks "$SKILLS_DIR"

  # If skills dir is empty (first install was dev mode), re-download
  if [[ ! -d "$SKILLS_DIR/shared" ]]; then
    log_info "No release skills found — downloading latest..."
    local release_json
    release_json="$(fetch_latest_release)"
    local tag
    tag="$(get_release_tag "$release_json")"
    local tarball_name="spectra-${tag}.tar.gz"
    local tarball_url checksums_url
    tarball_url="$(get_release_asset_url "$release_json" "$tarball_name")"
    checksums_url="$(get_release_asset_url "$release_json" "checksums.txt")"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "$tmp_dir/$tarball_name" "$tarball_url"
    curl -fsSL -o "$tmp_dir/checksums.txt" "$checksums_url"
    verify_checksum "$tmp_dir/$tarball_name" "$tmp_dir/checksums.txt"

    mkdir -p "$SKILLS_DIR"
    tar -xzf "$tmp_dir/$tarball_name" -C "$SKILLS_DIR/"
    rm -rf "$tmp_dir"

    create_skill_symlinks "$SKILLS_DIR"
    echo "${tag#v}" > "$VERSION_FILE"
  fi

  echo "release" > "$MODE_FILE"
  rm -f "$SPECTRA_HOME/dev-repo" "$SPECTRA_HOME/dev-link-manifest.json"

  log_success "Reverted to release mode"
}

cmd_status() {
  require_installed
  log_header "Spectra Status"

  local version
  version="$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")"
  local mode
  mode="$(cat "$MODE_FILE" 2>/dev/null || echo "unknown")"

  echo "  Version:  $version"
  if [[ "$mode" == "dev" ]]; then
    local repo
    repo="$(cat "$SPECTRA_HOME/dev-repo" 2>/dev/null || echo "unknown")"
    echo "  Mode:     dev (linked to $repo)"
  else
    echo "  Mode:     release"
  fi

  # Check for latest version
  if local release_json; release_json="$(fetch_latest_release 2>/dev/null)"; then
    local latest
    latest="$(get_release_tag "$release_json" 2>/dev/null || echo "")"
    latest="${latest#v}"
    if [[ -n "$latest" ]] && [[ "$latest" != "$version" ]]; then
      echo "  Latest:   $latest (update available)"
    fi
  fi

  echo ""
  echo "  Skills:"
  for skill in "${KNOWN_SKILLS[@]}"; do
    local link="$CLAUDE_SKILLS_DIR/$skill"
    if [[ -L "$link" ]]; then
      local target
      target="$(readlink "$link")"
      if [[ -d "$target" ]]; then
        echo "    ✓ $skill → $target"
      else
        echo "    ✗ $skill → $target (BROKEN)"
      fi
    else
      echo "    - $skill (not linked)"
    fi
  done

  echo ""
  echo "  Sessions:"
  for skill in deep-design decision-board code-review; do
    local dir="$SESSIONS_DIR/$skill"
    if [[ -d "$dir" ]]; then
      local size
      size="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
      local count
      count="$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
      echo "    $skill: $count sessions ($size)"
    fi
  done

  # Rollback availability
  if [[ -d "$SPECTRA_HOME/skills-prev" ]]; then
    echo ""
    echo "  Rollback: previous version available"
  fi

  # Permissions check
  echo ""
  local settings_file="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings_file" ]] && grep -q "json-write.sh" "$settings_file" 2>/dev/null; then
    echo "  Permissions: ✓ configured"
  else
    echo "  Permissions: ✗ not configured (run 'spectra doctor')"
  fi
}

cmd_doctor() {
  require_installed
  log_header "Spectra Doctor"
  local issues=0

  # Dependencies
  for dep in bash curl python3; do
    if command -v "$dep" >/dev/null 2>&1; then
      log_success "$dep found"
    else
      log_warn "$dep not found"
      issues=$((issues + 1))
    fi
  done

  # Checksum tool
  if detect_checksum_cmd >/dev/null 2>&1; then
    log_success "SHA-256 tool found"
  else
    log_warn "No SHA-256 tool (sha256sum or shasum) found"
    issues=$((issues + 1))
  fi

  local mode
  mode="$(cat "$MODE_FILE" 2>/dev/null || echo "release")"

  # Symlinks
  for skill in "${KNOWN_SKILLS[@]}"; do
    local link="$CLAUDE_SKILLS_DIR/$skill"
    if [[ -L "$link" ]]; then
      local target
      target="$(readlink "$link")"
      if [[ -d "$target" ]]; then
        # Mode-aware verification
        if [[ "$mode" == "release" ]] && [[ "$target" != "$SKILLS_DIR/$skill" ]]; then
          log_warn "$skill: points to $target (expected $SKILLS_DIR/$skill)"
          issues=$((issues + 1))
        else
          log_success "$skill symlink OK"
        fi
      else
        log_warn "$skill: broken symlink → $target"
        issues=$((issues + 1))
      fi
    else
      log_warn "$skill: not linked"
      issues=$((issues + 1))
    fi
  done

  # Permissions
  local settings_file="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings_file" ]]; then
    local spectra_perms
    spectra_perms="$(get_spectra_permissions)"
    local missing_count
    missing_count="$(python3 -c "
import json
settings = json.load(open('$settings_file'))
spectra = json.loads('$spectra_perms')
allow = settings.get('permissions', {}).get('allow', [])
missing = [p for p in spectra if p not in allow]
print(len(missing))
" 2>/dev/null || echo "unknown")"
    if [[ "$missing_count" == "0" ]]; then
      log_success "All permissions configured"
    else
      log_warn "$missing_count Spectra permission(s) missing from settings.json"
      log_info "  Fix: spectra update (re-merges permissions)"
      issues=$((issues + 1))
    fi
  else
    log_warn "settings.json not found"
    issues=$((issues + 1))
  fi

  # Session directories
  for skill in deep-design decision-board code-review; do
    local dir="$SESSIONS_DIR/$skill"
    if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
      log_success "$skill session directory OK"
    elif [[ -d "$dir" ]]; then
      log_warn "$skill session directory not writable"
      issues=$((issues + 1))
    else
      log_warn "$skill session directory missing"
      log_info "  Fix: mkdir -p $dir"
      issues=$((issues + 1))
    fi
  done

  # Compatibility symlinks
  for skill in deep-design decision-board code-review; do
    local compat="$CLAUDE_HOME/${skill}-sessions"
    if [[ -L "$compat" ]]; then
      # Check if any active sessions exist
      local active_sentinel="$SPECTRA_HOME/.active-${skill}-session"
      if [[ -f "$active_sentinel" ]]; then
        log_info "Compat symlink ${skill}-sessions exists (active session detected — keeping)"
      else
        log_info "Compat symlink ${skill}-sessions can be removed"
        log_info "  Fix: rm $compat"
      fi
    fi
  done

  # Dev mode checks
  if [[ "$mode" == "dev" ]]; then
    local repo
    repo="$(cat "$SPECTRA_HOME/dev-repo" 2>/dev/null || echo "")"
    if [[ -n "$repo" ]] && [[ -d "$repo" ]]; then
      log_success "Dev repo exists: $repo"
    else
      log_warn "Dev repo missing: $repo"
      log_info "  Fix: spectra unlink"
      issues=$((issues + 1))
    fi
  fi

  echo ""
  if [[ "$issues" -eq 0 ]]; then
    log_success "No issues found"
  else
    log_warn "$issues issue(s) found"
  fi
}

cmd_backup() {
  require_installed
  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    list)
      log_header "Settings Backups"
      if [[ -d "$BACKUPS_DIR" ]]; then
        local count=0
        while IFS= read -r f; do
          local ts
          ts="$(basename "$f" | sed 's/settings\.json\.//')"
          echo "  $ts  $(du -h "$f" | awk '{print $1}')"
          count=$((count + 1))
        done < <(ls -t "$BACKUPS_DIR"/settings.json.* 2>/dev/null)
        if [[ "$count" -eq 0 ]]; then
          log_info "No backups found"
        fi
      else
        log_info "No backups directory"
      fi
      ;;

    restore)
      log_header "Restore Settings"
      local timestamp="${1:-}"
      local backup_file

      if [[ -n "$timestamp" ]]; then
        backup_file="$BACKUPS_DIR/settings.json.$timestamp"
      else
        backup_file="$(ls -t "$BACKUPS_DIR"/settings.json.* 2>/dev/null | head -1)"
      fi

      if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        log_error "Backup not found${timestamp:+: $timestamp}"
        exit 1
      fi

      # Validate
      python3 -c "import json; json.load(open('$backup_file'))" 2>/dev/null \
        || { log_error "Backup is not valid JSON"; exit 1; }

      # Backup current before restoring
      settings_backup

      acquire_lock
      cp "$backup_file" "$CLAUDE_HOME/settings.json"
      release_lock

      log_success "Restored from: $(basename "$backup_file")"
      ;;

    *)
      log_error "Usage: spectra backup <list|restore> [timestamp]"
      exit 1
      ;;
  esac
}

cmd_help() {
  cat <<EOF
spectra — Spectra CLI for managing multi-agent skills

Usage: spectra <command> [options]

Commands:
  install           Install Spectra from latest release
  update            Update to latest release
  rollback          Roll back to previous version
  uninstall         Remove Spectra
  link <path>       Switch to dev mode (symlink to repo)
  unlink            Revert to release mode
  status            Show installation status
  doctor            Diagnose and suggest fixes
  backup list       List settings.json backups
  backup restore    Restore a settings.json backup
  version           Show version
  help              Show this help

EOF
}

cmd_version() {
  if [[ -f "$VERSION_FILE" ]]; then
    echo "spectra $(cat "$VERSION_FILE")"
  else
    echo "spectra $SPECTRA_VERSION (not installed)"
  fi
}

# --- Main dispatch ---

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    install)          cmd_install "$@" ;;
    update)           cmd_update "$@" ;;
    rollback)         cmd_rollback "$@" ;;
    uninstall)        cmd_uninstall "$@" ;;
    link)             cmd_link "$@" ;;
    unlink)           cmd_unlink "$@" ;;
    status)           cmd_status "$@" ;;
    doctor)           cmd_doctor "$@" ;;
    backup)           cmd_backup "$@" ;;
    help|--help|-h)   cmd_help ;;
    version|--version|-v) cmd_version ;;
    *)
      log_error "Unknown command: $cmd"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
```

**Step 2: Make executable and run ShellCheck**

Run: `chmod +x bin/spectra && npx shellcheck bin/spectra`
Expected: PASS or only informational notes (SC2064 is intentional)

**Step 3: Commit**

```bash
git add bin/spectra
git commit -m "feat: add spectra CLI with all commands

Implements install, update, rollback, uninstall, link, unlink,
status, doctor, and backup commands with atomic swap, mkdir-based
locking, SHA-256 verification, and settings.json merge protocol."
```

---

## Task 3: Rewrite `install.sh` as curl-pipe-bash entry point

**Files:**
- Modify: `install.sh`

The current `install.sh` is a simple symlink creator (8 lines). Rewrite it as a
curl-pipe-bash entry point that downloads and runs `spectra install`.

**Step 1: Read current install.sh**

Run: Read `install.sh` (already read above — 8-line symlink creator)

**Step 2: Rewrite `install.sh`**

Replace the entire file with the curl-pipe-bash installer:

```bash
#!/bin/bash
# Spectra Installer — curl -fsSL <url> | bash
# All logic inside main() so partial downloads don't execute.
set -euo pipefail

GITHUB_REPO="dnhess/spectra"
SPECTRA_HOME="$HOME/.spectra"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "  $*"; }
success() { echo "  ✓ $*"; }
warn() { echo "  ! $*" >&2; }

detect_checksum_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    die "No SHA-256 tool found (need sha256sum or shasum)"
  fi
}

main() {
  echo ""
  echo "=== Spectra Installer ==="
  echo ""

  # Pre-flight
  [[ "${BASH_VERSINFO[0]}" -ge 3 ]] || die "Bash >= 3.2 required (found ${BASH_VERSION})"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found — skills require it at runtime"
  fi
  local checksum_cmd
  checksum_cmd="$(detect_checksum_cmd)"

  if [[ -d "$SPECTRA_HOME" ]]; then
    die "Spectra is already installed at $SPECTRA_HOME. Use 'spectra update' instead."
  fi

  # Fetch latest release
  info "Fetching latest release..."
  local release_json
  release_json="$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest")" \
    || die "Failed to fetch release info"

  local tag version
  tag="$(echo "$release_json" | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")"
  version="${tag#v}"
  info "Latest version: $version"

  local tarball_name="spectra-${tag}.tar.gz"

  # Get asset URLs from the same API response
  local tarball_url checksums_url
  tarball_url="$(echo "$release_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a['name'] == '$tarball_name':
        print(a['browser_download_url']); sys.exit(0)
sys.exit(1)
")" || die "Tarball not found in release assets"

  checksums_url="$(echo "$release_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a['name'] == 'checksums.txt':
        print(a['browser_download_url']); sys.exit(0)
sys.exit(1)
")" || die "checksums.txt not found in release assets"

  # Download
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" EXIT

  info "Downloading $tarball_name..."
  curl -fsSL -o "$tmp_dir/$tarball_name" "$tarball_url"
  curl -fsSL -o "$tmp_dir/checksums.txt" "$checksums_url"

  # Verify checksum
  local expected actual
  expected="$(grep "$tarball_name" "$tmp_dir/checksums.txt" | awk '{print $1}')"
  actual="$($checksum_cmd "$tmp_dir/$tarball_name" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    die "Checksum mismatch! Expected: $expected, Got: $actual"
  fi
  success "Checksum verified"

  # Extract
  mkdir -p "$SPECTRA_HOME"/{skills,sessions,backups,bin}
  tar -xzf "$tmp_dir/$tarball_name" -C "$SPECTRA_HOME/skills/"
  success "Extracted skills"

  # Install CLI and json-write.sh
  if [[ -f "$SPECTRA_HOME/skills/bin/spectra" ]]; then
    cp "$SPECTRA_HOME/skills/bin/spectra" "$SPECTRA_HOME/bin/spectra"
    chmod +x "$SPECTRA_HOME/bin/spectra"
  else
    die "CLI script not found in tarball"
  fi
  if [[ -f "$SPECTRA_HOME/skills/bin/json-write.sh" ]]; then
    cp "$SPECTRA_HOME/skills/bin/json-write.sh" "$SPECTRA_HOME/bin/json-write.sh"
    chmod +x "$SPECTRA_HOME/bin/json-write.sh"
  fi
  rm -rf "$SPECTRA_HOME/skills/bin"

  echo "$version" > "$SPECTRA_HOME/version"
  echo "release" > "$SPECTRA_HOME/mode"
  success "Installed version $version"

  # Symlinks into ~/.claude/skills/
  local claude_skills="$HOME/.claude/skills"
  mkdir -p "$claude_skills"
  for skill in shared deep-design decision-board code-review; do
    if [[ -d "$SPECTRA_HOME/skills/$skill" ]]; then
      ln -sfn "$SPECTRA_HOME/skills/$skill" "$claude_skills/$skill"
      success "Linked $skill"
    fi
  done

  # Session directories + compat symlinks
  for skill in deep-design decision-board code-review; do
    mkdir -p "$SPECTRA_HOME/sessions/$skill"
    local old_path="$HOME/.claude/${skill}-sessions"
    if [[ ! -e "$old_path" ]]; then
      ln -sfn "$SPECTRA_HOME/sessions/$skill" "$old_path"
      info "Created compat symlink: ${skill}-sessions"
    fi
  done

  # Configure permissions
  local settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    cp "$settings_file" "$SPECTRA_HOME/backups/settings.json.$(date +%Y%m%d-%H%M%S)"
    success "Backed up settings.json"
  fi

  local current="{}"
  [[ -f "$settings_file" ]] && current="$(cat "$settings_file")"

  local updated
  updated="$(echo "$current" | python3 -c "
import sys, json
settings = json.load(sys.stdin)
spectra_perms = [
    'Bash(mkdir -p ~/.spectra/sessions/*)',
    'Bash(bash ~/.spectra/bin/json-write.sh *)',
    'Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)',
    'Write(~/.spectra/sessions/**)',
    'Read(~/.spectra/sessions/**)',
    'Glob(~/.spectra/sessions/**)',
    'Write(~/.spectra/.active-*)'
]
perms = settings.get('permissions', {})
allow = perms.get('allow', [])
for p in spectra_perms:
    if p not in allow:
        allow.append(p)
perms['allow'] = allow
settings['permissions'] = perms
json.dump(settings, sys.stdout, indent=2)
print()
")"

  echo "$updated" | python3 -c "import sys, json; json.load(sys.stdin)" \
    || die "Generated invalid settings.json"

  local tmp_settings="$settings_file.tmp.$$"
  echo "$updated" > "$tmp_settings"
  mv "$tmp_settings" "$settings_file"
  success "Permissions configured"

  # PATH
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$SPECTRA_HOME/bin/spectra" "$HOME/.local/bin/spectra"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "\$HOME/.local/bin is not in your PATH"
    info "  Add to your shell profile:"
    info "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  # Cleanup
  rm -rf "$tmp_dir"
  trap - EXIT

  echo ""
  echo "=== Install Complete ==="
  echo ""
  info "Version: $version"
  info "Home:    $SPECTRA_HOME"
  info "Skills:  shared, deep-design, decision-board, code-review"
  echo ""
  info "Run 'spectra status' to verify installation"
  info "Run 'spectra doctor' to check health"
}

# main() is the last callable — bash must parse the entire script first
main
```

**Step 3: Run ShellCheck**

Run: `npx shellcheck install.sh`
Expected: PASS

**Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: rewrite install.sh as curl-pipe-bash installer

Replaces the simple symlink creator with a full installer that
downloads from GitHub releases, verifies SHA-256 checksums,
configures permissions, and sets up ~/.spectra/ directory."
```

---

## Task 4: Add `.github/workflows/release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Write the release workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

permissions:
  contents: write

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DavidAnson/markdownlint-cli2-action@v19
        with:
          globs: "**/*.md"
      - uses: ludeeus/action-shellcheck@master
        with:
          scandir: "."
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm install --save-dev @commitlint/cli @commitlint/config-conventional
      - run: npx commitlint --from HEAD~1

  release:
    name: Build & Release
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Extract version from tag
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Build tarball
        run: |
          tarball_name="spectra-${GITHUB_REF_NAME}.tar.gz"
          tar -czf "$tarball_name" \
            --exclude='node_modules' \
            --exclude='.git' \
            --exclude='.github' \
            --exclude='docs' \
            --exclude='.husky' \
            --exclude='.claude' \
            --exclude='package.json' \
            --exclude='package-lock.json' \
            --exclude='.commitlintrc.yml' \
            --exclude='.markdownlint.yml' \
            --exclude='.markdownlintignore' \
            --exclude='.gitignore' \
            --exclude='CONTRIBUTING.md' \
            --exclude='CODE_OF_CONDUCT.md' \
            --exclude='CODEOWNERS' \
            --exclude='LICENSE' \
            bin/ \
            shared/ \
            deep-design/ \
            decision-board/ \
            code-review/ \
            CHANGELOG.md \
            README.md
          echo "tarball_name=$tarball_name" >> "$GITHUB_ENV"

      - name: Validate tarball
        run: |
          mkdir -p /tmp/validate
          tar -xzf "$tarball_name" -C /tmp/validate
          # Verify expected structure exists
          test -f /tmp/validate/bin/spectra
          test -f /tmp/validate/bin/json-write.sh
          test -d /tmp/validate/shared
          test -d /tmp/validate/deep-design
          test -d /tmp/validate/decision-board
          test -d /tmp/validate/code-review
          echo "Tarball structure validated"

      - name: Generate checksums
        run: sha256sum "$tarball_name" > checksums.txt

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: |
            ${{ env.tarball_name }}
            checksums.txt
```

**Step 2: Run YAML lint (basic check)**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" 2>/dev/null || echo "Install pyyaml to validate"`
Expected: No error (or skip if pyyaml not installed)

**Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow with SHA-256 checksums

Triggers on v*.*.* tags. Builds tarball, validates structure,
generates SHA-256 checksums, and publishes GitHub release."
```

---

## Task 5: Migrate session paths in `shared/` files

**Files:**
- Modify: `shared/orchestration.md`
- Modify: `shared/event-schemas-base.md`
- Modify: `shared/composition.md`
- Modify: `shared/security.md`

This task updates all `~/.claude/{skill}-sessions/` references to
`~/.spectra/sessions/{skill}/` and all `.active-{skill}-session` sentinel
references from `~/.claude/` to `~/.spectra/`.

**Step 1: Search for all references to update**

Run: `grep -rn '~/.claude/.*-sessions' shared/`
Run: `grep -rn '\.active-.*-session' shared/`

Identify each reference and determine whether it's:
- A concrete path to update (change `~/.claude/` to `~/.spectra/sessions/`)
- A template/pattern like `{sessions_root}` (may not need changing)
- Documentation about the old paths (update to new)

**Step 2: Update `shared/orchestration.md`**

Replace all concrete session path references:
- `~/.claude/{skill}-sessions/` → `~/.spectra/sessions/{skill}/`
- `~/.claude/.active-{skill}-session` → `~/.spectra/.active-{skill}-session`

Also update the agent prompt template's JSON serialization line:
- `python3 -c "import json; ..."` → `bash ~/.spectra/bin/json-write.sh` (where applicable)

**Note:** The agent prompt template line `Use python3 for JSON serialization: python3 -c "import json; ..."` should become `Use json-write.sh for output: bash ~/.spectra/bin/json-write.sh <output-path>` or similar. Read the full orchestration.md to determine exact changes needed.

**Step 3: Update `shared/event-schemas-base.md`**

Update any session path examples or references.

**Step 4: Update `shared/composition.md`**

Update session directory references.

**Step 5: Update `shared/security.md`**

Update path references in audit allowlists and directory constraints.

**Step 6: Run markdown lint**

Run: `npm run lint`
Expected: PASS

**Step 7: Commit**

```bash
git add shared/
git commit -m "refactor: migrate shared/ session paths to ~/.spectra/

Updates orchestration.md, event-schemas-base.md, composition.md, and
security.md from ~/.claude/{skill}-sessions/ to
~/.spectra/sessions/{skill}/."
```

---

## Task 6: Migrate session paths in skill SKILL.md files

**Files:**
- Modify: `deep-design/SKILL.md`
- Modify: `deep-design/event-schemas.md`
- Modify: `decision-board/SKILL.md`
- Modify: `decision-board/event-schemas.md`
- Modify: `code-review/SKILL.md`
- Modify: `code-review/event-schemas.md`

**Step 1: Search for references**

Run: `grep -rn '~/.claude/.*-sessions' deep-design/ decision-board/ code-review/`
Run: `grep -rn '\.active-.*-session' deep-design/ decision-board/ code-review/`

**Step 2: Update each skill's SKILL.md**

For each skill, update:
- `~/.claude/deep-design-sessions/` → `~/.spectra/sessions/deep-design/`
- `~/.claude/decision-board-sessions/` → `~/.spectra/sessions/decision-board/`
- `~/.claude/code-review-sessions/` → `~/.spectra/sessions/code-review/`
- `~/.claude/.active-{skill}-session` → `~/.spectra/.active-{skill}-session`
- Agent prompt template JSON serialization references (if skill-specific overrides exist)

**Step 3: Update each skill's event-schemas.md**

Update manifest path references and session path examples.

**Step 4: Run markdown lint**

Run: `npm run lint`
Expected: PASS

**Step 5: Commit**

```bash
git add deep-design/ decision-board/ code-review/
git commit -m "refactor: migrate skill session paths to ~/.spectra/

Updates SKILL.md and event-schemas.md for deep-design, decision-board,
and code-review from ~/.claude/{skill}-sessions/ to
~/.spectra/sessions/{skill}/."
```

---

## Task 7: Update README.md, CONTRIBUTING.md, and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `CLAUDE.md`

**Step 1: Update README.md**

- Replace the Installation section with curl-based install
- Update the permissions block to use new paths and `json-write.sh`
- Update Repository Structure to show `bin/` directory
- Add `code-review` to Available Skills section (if not already there)
- Update the "Adding New Skills" section to reference `spectra` CLI

New Installation section:

```markdown
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
```

Update the permissions block to match the revised design:

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir -p ~/.spectra/sessions/*)",
      "Bash(bash ~/.spectra/bin/json-write.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)",
      "Write(~/.spectra/sessions/**)",
      "Read(~/.spectra/sessions/**)",
      "Glob(~/.spectra/sessions/**)",
      "Write(~/.spectra/.active-*)"
    ]
  }
}
```

**Step 2: Update CONTRIBUTING.md**

- Update "Getting Started" to reference `spectra link .` instead of `./install.sh`
- Update the "Session directories live under" line to `~/.spectra/sessions/{skill}/`
- Update "Add a symlink line to install.sh" guidance

**Step 3: Update CLAUDE.md**

- Update "Session directories live under" to `~/.spectra/sessions/{skill}/`
- Update the `install.sh` reference in Editing Guidelines
- Add `bin/` to the Structure section
- Update the permission convention from `python3 -c` to `json-write.sh`

**Step 4: Run markdown lint**

Run: `npm run lint`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md CONTRIBUTING.md CLAUDE.md
git commit -m "docs: update installation and path references for Spectra CLI

Replaces git clone + install.sh with curl-based install. Updates
permissions to use json-write.sh. Migrates session paths to
~/.spectra/sessions/."
```

---

## Task 8: Add CI lint rule for hardcoded `~/.claude/` session paths

**Files:**
- Modify: `.github/workflows/lint.yml`

Add a job that greps for hardcoded `~/.claude/` session paths in skill files
to prevent regression after migration.

**Step 1: Add the lint job**

Add to `.github/workflows/lint.yml`:

```yaml
  path-lint:
    name: Session Path Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for hardcoded ~/.claude/ session paths
        run: |
          # Grep for old-style session paths in skill and shared files
          # Exclude docs/plans/ (design docs may reference old paths)
          # Exclude CHANGELOG.md (historical entries)
          if grep -rn '~/.claude/.*-sessions/' \
            --include='*.md' \
            --exclude-dir='docs' \
            --exclude='CHANGELOG.md' \
            shared/ deep-design/ decision-board/ code-review/ README.md CONTRIBUTING.md CLAUDE.md; then
            echo "::error::Found hardcoded ~/.claude/ session paths. Use ~/.spectra/sessions/{skill}/ instead."
            exit 1
          fi
          echo "No hardcoded session paths found"
```

**Step 2: Run a local check**

Run: `grep -rn '~/.claude/.*-sessions/' --include='*.md' --exclude-dir='docs' --exclude='CHANGELOG.md' shared/ deep-design/ decision-board/ code-review/ README.md CONTRIBUTING.md CLAUDE.md`
Expected: No matches (after Tasks 5-7 are complete)

**Step 3: Commit**

```bash
git add .github/workflows/lint.yml
git commit -m "ci: add lint rule for hardcoded ~/.claude/ session paths

Prevents regression by failing CI if any skill or shared file
references the old ~/.claude/{skill}-sessions/ path pattern."
```

---

## Task 9: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

**Step 1: Add entries under [Unreleased]**

Add to the `### Added` section:

```markdown
- **Spectra CLI** (`bin/spectra`) — install, update, rollback, uninstall, link, unlink, status, doctor, backup commands
- `bin/json-write.sh` — scoped JSON writer replacing broad `python3 -c *` permission
- `.github/workflows/release.yml` — automated release with SHA-256 checksums
- Curl-based installer (`install.sh` rewrite) with `main()` wrapper, checksum verification
- Atomic swap protocol for safe skill updates with trap-based rollback
- mkdir-based settings.json locking with stale lock detection
- Compare-and-swap settings.json writes to prevent concurrent modification
- Migration compatibility symlinks (`~/.claude/{skill}-sessions/` → `~/.spectra/sessions/{skill}/`)
- CI lint rule for hardcoded `~/.claude/` session paths
```

Add a `### Changed` entry:

```markdown
- Session paths migrated from `~/.claude/{skill}-sessions/` to `~/.spectra/sessions/{skill}/`
- Permission `Bash(python3 -c *)` replaced with `Bash(bash ~/.spectra/bin/json-write.sh *)`
- `install.sh` rewritten from symlink creator to full curl-pipe-bash installer
- Installation uses `~/.spectra/` as home directory with symlinks into `~/.claude/skills/`
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG with Spectra CLI and installer entries"
```

---

## Task 10: Final verification

**Step 1: Run all linters**

Run: `npm run lint`
Expected: PASS

**Step 2: Run ShellCheck on all shell scripts**

Run: `npx shellcheck bin/spectra bin/json-write.sh install.sh shared/tools/jsonl-utils.sh`
Expected: PASS (or only intentional SC2064 suppression)

**Step 3: Verify no old session paths remain in skill files**

Run: `grep -rn '~/.claude/.*-sessions/' --include='*.md' --exclude-dir='docs' --exclude='CHANGELOG.md' shared/ deep-design/ decision-board/ code-review/ README.md CONTRIBUTING.md CLAUDE.md`
Expected: No matches

**Step 4: Verify file structure**

Run: `find bin/ -type f && ls .github/workflows/`
Expected:
```
bin/spectra
bin/json-write.sh
lint.yml
release.yml
```

**Step 5: Review the full diff**

Run: `git diff main --stat`
Expected: Changes in bin/, install.sh, .github/workflows/, shared/, deep-design/, decision-board/, code-review/, README.md, CONTRIBUTING.md, CLAUDE.md, CHANGELOG.md

**Step 6: Commit any fixes**

If any issues found, fix and commit with appropriate message.
