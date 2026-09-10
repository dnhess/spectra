#!/usr/bin/env bats
# Self-contained Spectra plugin (Claude / Codex / Astra). No CLI required.

load test_helper/common-setup

setup() {
  _common_setup
}

teardown() {
  _common_teardown
}

@test "Claude marketplace points at the self-contained plugin folder" {
  run python3 - "$PROJECT_ROOT/.claude-plugin/marketplace.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["name"] == "spectra"
assert data["plugins"][0]["name"] == "spectra"
assert data["plugins"][0]["source"] == "./plugin"
print("ok")
PY
  assert_success
  assert_output --partial "ok"
}

@test "Codex marketplace points at the same plugin folder" {
  run python3 - "$PROJECT_ROOT/.agents/plugins/marketplace.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["plugins"][0]["name"] == "spectra"
source = data["plugins"][0]["source"]
path = source["path"] if isinstance(source, dict) else source
assert path in ("./plugin", "./plugin/")
print("ok")
PY
  assert_success
}

@test "plugin is self-contained with one portable skill" {
  [[ -f "$PROJECT_ROOT/plugin/.claude-plugin/plugin.json" ]]
  [[ -f "$PROJECT_ROOT/plugin/plugin.json" ]]
  [[ -f "$PROJECT_ROOT/plugin/skills/spectra/SKILL.md" ]]
  [[ -f "$PROJECT_ROOT/plugin/skills/spectra/references/protocol.md" ]]
  [[ -f "$PROJECT_ROOT/plugin/skills/spectra/references/personas.md" ]]
  run grep -R -E '\\.\\.\\./|~/.claude/skills' "$PROJECT_ROOT/plugin/skills/spectra" || true
  refute_output --partial "~/.claude/skills"
}

@test "portable skill frontmatter matches Agent Skills name rules" {
  run python3 - "$PROJECT_ROOT/plugin/skills/spectra/SKILL.md" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
fm = text.split("---", 2)[1]
assert "name: spectra" in fm
assert "description:" in fm
low = fm.lower()
assert "frontier" in low or "subagent" in low or "token" in low
print("ok")
PY
  assert_success
}

@test "legacy SessionStart linker still works for the fat Claude skills" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" HOME="$HOME" bash "$PROJECT_ROOT/scripts/link-host.sh"
  assert_success
  [[ -f "$HOME/.claude/skills/shared/orchestration.md" ]]
}

@test "init-session.sh creates the session tree" {
  run env HOME="$HOME" bash "$PROJECT_ROOT/plugin/skills/spectra/scripts/init-session.sh" decision-board auth-mfa
  assert_success
  session_dir="$output"
  [[ -d "$session_dir/opening" ]]
  [[ -d "$session_dir/discussion/round-1" ]]
  [[ -d "$session_dir/final-positions" ]]
}

@test "personas.md names every Quick core persona" {
  personas="$PROJECT_ROOT/plugin/skills/spectra/references/personas.md"
  for id in system-architect security-expert pm be-engineer architect pragmatist devils-advocate risk-assessor security-auditor reliability-engineer test-strategist maintainability-advocate package-validator intent-auditor security-challenger coherence-checker alignment-auditor contradiction-detector constraint-monitor devils-examiner; do
    grep -q "$id" "$personas"
  done
}

@test "protocol tells the moderator to poll opening files not chat" {
  run grep -E "poll the filesystem|Do not wait on host chat" "$PROJECT_ROOT/plugin/skills/spectra/references/protocol.md" "$PROJECT_ROOT/plugin/skills/spectra/SKILL.md"
  assert_success
  assert_output --partial "poll the filesystem"
  assert_output --partial "Do not wait on host chat"
}

@test "governor skill routes economical vs frontier and requires approval" {
  skill="$PROJECT_ROOT/plugin/skills/spectra/SKILL.md"
  proto="$PROJECT_ROOT/plugin/skills/spectra/references/protocol.md"
  grep -q "economical" "$skill" "$proto"
  grep -q "frontier" "$skill"
  grep -q "approval" "$skill"
  grep -q 'escalate' "$skill" "$proto"
}

@test "route-plan example JSON is valid" {
  run python3 - "$PROJECT_ROOT/plugin/skills/spectra/references/examples/route-plan.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["class"] in ("economical", "standard", "frontier")
assert "steps" in data and len(data["steps"]) >= 1
for step in data["steps"]:
    assert step["class"] in ("economical", "standard", "frontier")
    assert "id" in step and "goal" in step
print("ok")
PY
  assert_success
}

@test "decision-board example synthesis JSON is valid" {
  run python3 - "$PROJECT_ROOT/plugin/skills/spectra/references/examples/decision-board-quick.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
for key in ("workflow", "recommendation", "dissent", "conditions", "persona_count"):
    assert key in data, key
assert data["workflow"] == "decision-board"
assert data["persona_count"] >= 4
print("ok")
PY
  assert_success
}
