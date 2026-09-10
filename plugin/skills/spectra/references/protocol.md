# Spectra governor protocol

The host thread is expensive. Workers are cheap. Files are the join signal.

## Classes

- **economical** — search, read, summarize, tests, boilerplate. Must be a subagent. Smallest/fastest model the host offers.
- **standard** — bounded implementation or review. Subagent. Mid-tier if available, else economical.
- **frontier** — plan, architecture, conflict, final merge of disagreeing workers. This thread only, after user approval.

Default: if unsure, `economical`. Never upgrade a step to `frontier` without asking.

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
