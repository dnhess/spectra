# Spectra protocol

Coordination is a **typed artifact ledger**, not chat:

- Workers write JSON files. You read files. Nobody messages workers as a bus.
- You are the only writer of `synthesis-brief.json`, `handoff.md`, and round briefs.
- Agent output files are write-once. First valid file wins.

## Join rule

After spawn, **poll the filesystem**. Completeness is “every expected `opening/<persona-id>.json` exists and parses,” not a chat callback, tool result, or “all subagents finished” notice. Hosts drop those notices. If a file is missing past the deadline, record that persona as timed out and synthesize with whoever landed.

## Session layout

```text
~/.spectra/sessions/<workflow>/<topic>-<timestamp>/
  opening/<persona-id>.json
  discussion/round-1/round-brief.json
  synthesis-brief.json
  handoff.md
```

## Worker prompt (paste into each subagent)

```text
You are the <persona-id> persona. Read only the persona brief I give you and the subject.
Write one JSON object to <absolute-opening-path>. Do not read other agents' files.
Do not edit the user's project. No markdown fences around the file contents.
Use the opening schema for this workflow. Stop after the file is written.
```

## Opening JSON

Decision-board: `agent`, `preferred_option`, `confidence` (0-1), `conditions` (array), `reasoning`, `options_assessed` (array).

Deep-design / peer-review: `agent`, `findings` (array of `{severity, title, evidence}`), `recommendation`.

Trust-layer / coherence-monitor: `agent`, `verdict` (`accept`|`reject`|`revise`), `findings` (array), `reasoning`.

## Synthesis

`synthesis-brief.json` must include `workflow`, `recommendation`, `dissent`, `conditions`, `persona_count`.

`handoff.md` must include Session, Key Findings, Unresolved, Recommendations.

See [examples/decision-board-quick.json](examples/decision-board-quick.json) for shape.
