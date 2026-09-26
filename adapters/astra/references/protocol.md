# Spectra protocol (Astra)

Coordination is a **typed artifact ledger**, not chat:

- Workers write JSON files. You read files. Nobody SendMessages.
- You are the only writer of `synthesis-brief.json`, `handoff.md`, and round briefs.
- Agent output files are write-once. First valid file wins.

## Session layout

```text
~/.spectra/sessions/<workflow>/<topic>-<timestamp>/
  opening/<persona-id>.json
  discussion/round-1/round-brief.json
  final-positions/          # optional on quick
  synthesis-brief.json
  handoff.md
```

## Opening JSON

Decision-board: `agent`, `preferred_option`, `confidence` (0-1), `conditions` (array), `reasoning`, `options_assessed` (array).

Deep-design / peer-review: `agent`, `findings` (array of `{severity, title, evidence}`), `recommendation`.

Trust-layer / coherence-monitor: `agent`, `verdict` (`accept`|`reject`|`revise`), `findings` (array), `reasoning`.

## Synthesis

`synthesis-brief.json` must include `workflow`, `recommendation`, `dissent`, `conditions`, `persona_count`.

`handoff.md` must include Session, Key Findings, Unresolved, Recommendations.

## Do not

- Load Claude Code skills or `~/.claude/skills/**/SKILL.md`
- Copy this skill into a git repo's `.agents/skills` while developing Spectra
- Spawn nested `codex exec` workers (the isolated Codex adapter is a separate, fail-closed path)
- Invent personas that have no file under `personas/`
