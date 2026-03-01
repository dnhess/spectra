#!/usr/bin/env bash
# Common test setup for Spectra CLI bats tests

_common_setup() {
  # Load bats helpers from node_modules
  local project_root
  project_root="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  load "${project_root}/node_modules/bats-support/load"
  load "${project_root}/node_modules/bats-assert/load"

  # Export project root for access to bin/ and shared/
  export PROJECT_ROOT="$project_root"
  export SPECTRA_CLI="$project_root/bin/spectra"

  # Create isolated HOME so tests never touch real ~/.spectra or ~/.claude
  TEST_TEMP="$(mktemp -d)"
  export TEST_TEMP
  export HOME="$TEST_TEMP/home"
  mkdir -p "$HOME"

  # Set standard Spectra paths relative to isolated HOME
  export SPECTRA_HOME="$HOME/.spectra"
  export CLAUDE_HOME="$HOME/.claude"
  export CLAUDE_SKILLS_DIR="$CLAUDE_HOME/skills"
}

_common_teardown() {
  if [[ -n "${TEST_TEMP:-}" ]] && [[ -d "$TEST_TEMP" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

# Create the full ~/.spectra/ tree that require_installed expects
bootstrap_installed_state() {
  mkdir -p "$SPECTRA_HOME"/{skills,sessions,backups,bin}
  mkdir -p "$SPECTRA_HOME/sessions"/{deep-design,decision-board,code-review}
  mkdir -p "$CLAUDE_HOME/skills"

  # Version and mode files
  echo "0.2.0" > "$SPECTRA_HOME/version"
  echo "release" > "$SPECTRA_HOME/mode"

  # Copy CLI to expected location
  cp "$PROJECT_ROOT/bin/spectra" "$SPECTRA_HOME/bin/spectra"
  chmod +x "$SPECTRA_HOME/bin/spectra"

  if [[ -f "$PROJECT_ROOT/bin/json-write.sh" ]]; then
    cp "$PROJECT_ROOT/bin/json-write.sh" "$SPECTRA_HOME/bin/json-write.sh"
    chmod +x "$SPECTRA_HOME/bin/json-write.sh"
  fi

  # Create skill directories with minimal content
  for skill in shared deep-design decision-board code-review; do
    mkdir -p "$SPECTRA_HOME/skills/$skill"
    if [[ "$skill" != "shared" ]]; then
      touch "$SPECTRA_HOME/skills/$skill/SKILL.md"
      mkdir -p "$SPECTRA_HOME/skills/$skill/personas"
    fi
  done
  mkdir -p "$SPECTRA_HOME/skills/shared/tools"
  touch "$SPECTRA_HOME/skills/shared/orchestration.md"

  # Create symlinks
  for skill in shared deep-design decision-board code-review; do
    ln -sfn "$SPECTRA_HOME/skills/$skill" "$CLAUDE_SKILLS_DIR/$skill"
  done

  # Create settings.json with permissions
  mkdir -p "$CLAUDE_HOME"
  cat > "$CLAUDE_HOME/settings.json" <<'SETTINGS'
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
SETTINGS
}

# Create a minimal Spectra repo structure for link tests
create_fake_repo() {
  local repo_dir="${1:-$TEST_TEMP/fake-repo}"
  mkdir -p "$repo_dir"/{shared/tools,bin}
  touch "$repo_dir/install.sh"
  touch "$repo_dir/shared/orchestration.md"
  cp "$PROJECT_ROOT/bin/spectra" "$repo_dir/bin/spectra"
  chmod +x "$repo_dir/bin/spectra"
  if [[ -f "$PROJECT_ROOT/bin/json-write.sh" ]]; then
    cp "$PROJECT_ROOT/bin/json-write.sh" "$repo_dir/bin/json-write.sh"
    chmod +x "$repo_dir/bin/json-write.sh"
  fi

  for skill in deep-design decision-board code-review; do
    mkdir -p "$repo_dir/$skill/personas"
    touch "$repo_dir/$skill/SKILL.md"
  done

  echo "$repo_dir"
}

# ---------------------------------------------------------------------------
# Orchestration test helpers
# ---------------------------------------------------------------------------

# Create a session directory with standard subdirectories
# Usage: create_session_dir <skill> <topic>
# Sets SESSION_DIR to the created path
create_session_dir() {
  local skill="$1" topic="$2"
  local ts
  ts="$(date +%Y%m%dT%H%M%S)"
  SESSION_DIR="$SPECTRA_HOME/sessions/$skill/${topic}-${ts}"
  export SESSION_DIR
  mkdir -p "$SESSION_DIR"/{opening,discussion,final-positions}
  echo "$SESSION_DIR"
}

# Output a valid JSONL event line
# Usage: make_event <seq> <type> [session_id]
make_event() {
  local seq="$1" type="$2" session_id="${3:-test-session-001}"
  python3 -c "
import json, uuid, datetime
print(json.dumps({
    'event_id': str(uuid.uuid4()),
    'sequence_number': int('$seq'),
    'schema_version': '1.0.0',
    'session_id': '$session_id',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'type': '$type'
}))"
}

# Write .active-{skill}-session sentinel file
# Usage: make_sentinel <skill> <session_dir> <session_id>
make_sentinel() {
  local skill="$1" session_dir="$2" session_id="$3"
  local sentinel_path="$SPECTRA_HOME/.active-${skill}-session"
  python3 -c "
import json, datetime
print(json.dumps({
    'session_dir': '$session_dir',
    'session_id': '$session_id',
    'skill': '$skill',
    'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat()
}))" > "$sentinel_path"
  echo "$sentinel_path"
}

# Write session.lock with tier-based TTL
# Usage: make_lock <session_dir> <session_id> [tier]
make_lock() {
  local session_dir="$1" session_id="$2" tier="${3:-standard}"
  local ttl
  case "$tier" in
    quick)    ttl=15 ;;
    standard) ttl=30 ;;
    deep)     ttl=60 ;;
    *)        ttl=30 ;;
  esac
  python3 -c "
import json, datetime
print(json.dumps({
    'session_id': '$session_id',
    'tier': '$tier',
    'ttl_minutes': $ttl,
    'locked_at': datetime.datetime.now(datetime.timezone.utc).isoformat()
}))" > "$session_dir/session.lock"
}

# Write session-state.md checkpoint
# Usage: make_checkpoint <session_dir> <session_id> <phase>
make_checkpoint() {
  local session_dir="$1" session_id="$2" phase="$3"
  cat > "$session_dir/session-state.md" <<EOF
## Session

- **Session ID**: $session_id
- **Phase**: $phase

## Current Phase

$phase in progress.

## Recovery Instructions

Resume from phase $phase using session directory.
EOF
}

# Write handoff.md
# Usage: make_handoff <session_dir> <session_id>
make_handoff() {
  local session_dir="$1" session_id="$2"
  cat > "$session_dir/handoff.md" <<EOF
## Session

- **Session ID**: $session_id

## Key Findings

- Finding 1: placeholder

## Unresolved

- Item 1: placeholder

## Recommendations

- Recommendation 1: placeholder
EOF
}

# Validate checkpoint has required sections
# Usage: validate_checkpoint <file>
validate_checkpoint() {
  local file="$1"
  local missing=()
  grep -q "^## Session" "$file" || missing+=("## Session")
  grep -q "^## Current Phase" "$file" || missing+=("## Current Phase")
  grep -q "^## Recovery Instructions" "$file" || missing+=("## Recovery Instructions")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing sections: ${missing[*]}" >&2
    return 1
  fi
}

# Validate handoff has required sections
# Usage: validate_handoff <file>
validate_handoff() {
  local file="$1"
  local missing=()
  grep -q "^## Session" "$file" || missing+=("## Session")
  grep -qE "^## (Key Findings|Debate Outcome)" "$file" || missing+=("## Key Findings or ## Debate Outcome")
  grep -q "^## Unresolved" "$file" || missing+=("## Unresolved")
  grep -q "^## Recommendations" "$file" || missing+=("## Recommendations")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing sections: ${missing[*]}" >&2
    return 1
  fi
}

# Output a manifest JSONL line
# Usage: make_manifest_entry <session_id> <project> [tier] [quality]
make_manifest_entry() {
  local session_id="$1" project="$2" tier="${3:-standard}" quality="${4:-Full}"
  python3 -c "
import json, datetime
print(json.dumps({
    'session_id': '$session_id',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'project': '$project',
    'tier': '$tier',
    'agent_count': 7,
    'specialist_count': 1,
    'quality': '$quality',
    'duration_seconds': 480,
    'feedback_rating': None,
    'has_handoff': False,
    'session_dirname': None
}))"
}

# ---------------------------------------------------------------------------
# Update / release test helpers
# ---------------------------------------------------------------------------

# Create a fake release tarball mimicking a GitHub release asset.
# Sets env vars: SPECTRA_TEST_TAG, SPECTRA_TEST_TARBALL, SPECTRA_TEST_CHECKSUMS
#
# Usage: create_fake_tarball <output_dir> <tag>
#   output_dir — directory where tarball and checksums.txt are written
#   tag        — release tag, e.g. "v0.3.0"
create_fake_tarball() {
  local output_dir="$1"
  local tag="$2"
  mkdir -p "$output_dir"

  # Build a directory tree that matches what the installer expects
  local staging="$output_dir/staging"
  mkdir -p "$staging"/{shared/tools,bin}
  touch "$staging/shared/orchestration.md"

  for skill in deep-design decision-board code-review; do
    mkdir -p "$staging/$skill/personas"
    echo "# $skill SKILL.md ($tag)" > "$staging/$skill/SKILL.md"
  done

  # bin files
  cp "$PROJECT_ROOT/bin/spectra" "$staging/bin/spectra"
  chmod +x "$staging/bin/spectra"
  if [[ -f "$PROJECT_ROOT/bin/json-write.sh" ]]; then
    cp "$PROJECT_ROOT/bin/json-write.sh" "$staging/bin/json-write.sh"
    chmod +x "$staging/bin/json-write.sh"
  fi

  # Create tarball
  local tarball_name="spectra-${tag}.tar.gz"
  tar -czf "$output_dir/$tarball_name" -C "$staging" .

  # Create checksums file
  local checksum_cmd
  if command -v sha256sum >/dev/null 2>&1; then
    checksum_cmd="sha256sum"
  else
    checksum_cmd="shasum -a 256"
  fi
  (cd "$output_dir" && $checksum_cmd "$tarball_name" > checksums.txt)

  # Clean up staging
  rm -rf "$staging"

  # Export env vars for the test shim
  export SPECTRA_TEST_TAG="$tag"
  export SPECTRA_TEST_TARBALL="$output_dir/$tarball_name"
  export SPECTRA_TEST_CHECKSUMS="$output_dir/checksums.txt"
}
