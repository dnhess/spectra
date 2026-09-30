# Spectra governor protocol

The host thread is expensive. Workers are cheap. Files are the join signal.

## Classes

- **economical** — search, read, summarize, tests, boilerplate. Must be a subagent on a cheaper tier than this thread. Not necessarily the smallest model.
- **standard** — bounded implementation or review. Subagent. Mid-tier if available, else economical.
- **frontier** — plan, architecture, conflict, final merge of disagreeing workers. This thread only, after user approval.

Default: if unsure, `economical`. Never upgrade a step to `frontier` without asking.

## Model rule

Claude already mixes models when you ask it to orchestrate. A spawn can pass
Haiku, Sonnet, or Opus. Do not replace that with a blanket Haiku pin.

- Grunt work stays off this thread's model. On Claude, Haiku or Sonnet.
- A worker on this thread's model is `frontier`. Ask before it runs.
- Codex inherits the parent model unless the spawn sets one. Set a cheaper
  model for grunt work, or ask. Do not assume Claude's mix applies there.
- If the host cannot spawn at all, stop. Do not do the grep on this thread.

## Caps (proxy, not dollars)

Do not claim token or dollar cost. Enforce observable ceilings:

- max 8 worker spawns per session unless the user raises it
- max 2 concurrent workers
- max 15 minutes wall for a worker wave
- no extra wave if `summary.json` can be written from what landed

Record `{spawns, frontier_calls, skipped}` in `summary.json`.

## Join rule

After spawn, **poll the filesystem**. Completeness is “every expected `workers/<id>.json` exists and parses,” not a chat callback, tool result, or “all subagents finished” notice. Hosts drop those notices. If a file is missing past the deadline, mark that step `timed_out` and continue.

**Do not wait on host chat.**

## Worker prompt

```text
You are a Spectra economical worker. Goal: <goal>
Write one JSON object to <absolute-path>: {id, ok, notes, artifacts, escalate}.
escalate is "" or "frontier". Use "frontier" only if you cannot finish without the decider.
Do not message the governor, Codex, or Claude mid-run. Do not read other workers' files.
Do not call a frontier model. Stop after the file is written.
```

If `escalate` is `frontier` after join, ask the user, then do that step on this thread.

## plan.json

See [examples/route-plan.json](examples/route-plan.json).

## Deliberation (opt-in)

Only if the user asks for Spectra decision-board / deep-design / trust-layer. Then use [personas.md](personas.md) and write openings under `opening/`. Same join rule on those files. Do not use a persona panel to save tokens — it spends them.
