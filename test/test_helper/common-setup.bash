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
