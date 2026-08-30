# Codex-first agent-agnostic runtime spike

## Plan

- [x] Inventory the existing Claude-specific execution seam and preserve current behavior.
- [x] Define a versioned, provider-neutral runtime capability and work-item contract.
- [x] Add a Codex runtime adapter that can render and validate a bounded peer-review plan without making network calls.
- [x] Expose runtime inspection and dry-run planning through the Spectra CLI.
- [x] Add adapter conformance, CLI, packaging, permission, and failure-path tests.
- [x] Document the architecture, limitations, local-versus-offline distinction, and migration path.
- [x] Run focused tests, the full suite, linting, shell checks, JSON validation, Python compilation, and diff hygiene checks.

## Guardrails

- Existing Claude Code installation and workflows remain the default and must not regress.
- Tests must never launch a real model or transmit repository content.
- The core contract uses capabilities and model classes, not provider-specific tool or model names.
- MCP remains a context/tool boundary, not Spectra's internal scheduler.
- This phase proves one bounded `peer-review` quick workflow; it does not rewrite every skill.

## Review

- The runtime contract now represents a validated single-phase DAG with action dependencies,
  join quorum, deadlines, timeout behavior, cancellation policy, retries, logical path anchors,
  completion artifacts, model classes, and budget increments.
- The Codex adapter is explicitly planning-only. It reports `execution_enabled: false`, never
  invokes Codex, and never transmits project content. The local Codex CLI was detected during
  the installed smoke check.
- Release archives now include and validate the adapter; update tests prove release-mode
  dispatch reaches it.
- Reviewer P1 findings covering release packaging, flat-batch semantics, overstated
  capabilities, path anchoring, boolean counter acceptance, and Python compatibility were fixed.
- Verification: 351/351 Bats tests, 84 Markdown files, ShellCheck, ten JSON files, Python
  compilation, installed CLI smoke checks, and `git diff --check` all passed.

## Executable Codex Quick peer review

### Plan

- [x] Confirm the installed Codex non-interactive interface and document any local CLI blocker.
- [x] Specify a digest-bound preview/approval contract, trusted root bindings, and conservative hard limits.
- [x] Implement bounded asynchronous worker execution with timeouts, quorum, and cancellation cleanup; reject retries in the MVP.
- [x] Keep workers read-only and network-disabled; validate their structured output before atomic moderator writes.
- [x] Integrate budget preflight and provider-run accounting without counting rejected planned work.
- [x] Add fake-Codex tests for approval, confinement, budgets, bounded concurrency, quorum, and failure paths.
- [x] Update runtime capabilities, CLI help, release/docs, and preserve the existing Claude default.
- [x] Run the full verification suite and record the real-Codex smoke outcome without spending more calls on a known-costly configuration.

### Guardrails

- Execution is opt-in and requires an exact token emitted by preview; dry-run remains inert.
- The executable spike is limited to one Quick phase, at most four actions, and at most two concurrent workers.
- Tests never invoke a real model or transmit repository content.
- Spectra stages only explicitly bound inputs and workers never write the shared session directly;
  read-only Codex is not an OS-level filesystem read allowlist.
- The moderator is the sole artifact and budget-metrics writer.

### Review

- The executable slice is limited to one Quick peer-review opening fan-out: one to four
  independent workers, at most two concurrent Codex processes, no retries, and a 300-second
  maximum phase deadline.
- Preview binds the plan, roots, input and prompt hashes, output schema, Codex executable,
  model map, budget policy, trusted runtime code, and hard limits into an exact approval token.
- Workers operate on private snapshots and return schema-constrained JSON. Only validated
  artifacts are atomically published by the moderator; budget checks and updates are serialized.
- `model_calls` is explicitly a provider-process proxy because the CLI does not expose internal
  turn counts. Executable plans require `max_turns: 1` to mean one bounded provider run.
- Fake-runtime integration is passing. A real desktop Codex transport call succeeded, but the
  runtime injected roughly 10k-17k tokens of unrelated installed-skill context in diagnostics;
  further live smoke calls are paused until a dedicated minimal Codex profile exists.
- Verification: 365/365 repository tests, Markdown lint across 84 files, ShellCheck, runtime
  Python compilation, valid production JSON, and diff hygiene all pass. The intentionally
  truncated validation fixture remains excluded from production-JSON parsing by design.
