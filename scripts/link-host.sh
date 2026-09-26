#!/usr/bin/env bash
# Link Spectra skills into the Claude Code host paths so SKILL.md
# references to ~/.claude/skills/shared keep working without the CLI installer.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ ! -d "$ROOT/shared" ]] || [[ ! -d "$ROOT/deep-design" ]]; then
  echo "spectra link-host: plugin root is missing skill directories: $ROOT" >&2
  exit 1
fi

mkdir -p "$HOME/.claude/skills" "$HOME/.spectra/bin"
mkdir -p "$HOME/.spectra/sessions"/{deep-design,decision-board,peer-review,trust-layer,coherence-monitor}

for skill in shared deep-design decision-board peer-review trust-layer coherence-monitor; do
  ln -sfn "$ROOT/$skill" "$HOME/.claude/skills/$skill"
done

if [[ -f "$ROOT/bin/json-write.sh" ]]; then
  ln -sfn "$ROOT/bin/json-write.sh" "$HOME/.spectra/bin/json-write.sh"
  chmod +x "$ROOT/bin/json-write.sh" 2>/dev/null || true
fi

echo "spectra host links ready under $HOME/.claude/skills"
