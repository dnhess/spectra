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

## Minimal Codex execution profile

### Plan

- [x] Require an explicit, dedicated `CODEX_HOME` for preview and execute.
- [x] Run Codex with a private empty `HOME` while preserving only the dedicated authenticated profile.
- [x] Validate the profile path and bind its non-secret configuration manifest into approval.
- [x] Reject missing, symlinked, permissive, or changed execution profiles before worker launch.
- [x] Add fake-Codex coverage for environment isolation, profile mutation, and compatibility failures.
- [x] Update adapter capabilities, CLI help, packaging documentation, and runtime limitations.
- [x] Run focused and full verification without launching a real Codex worker.

### Guardrails

- No real Codex worker or model call runs during this slice.
- Authentication material is validated by type and permissions but never read, hashed, logged, or copied by the moderator.
- The execution profile is explicit and approval-bound; the executor never falls back to the user's profile.
- The private worker `HOME` contains no user skills, and executable plans cannot stage `.agents`.
- Existing Claude workflows and inert Codex validation/render/dry-run operations remain unchanged.

### Review

- Preview and execute now require an explicit owner-only profile containing nonempty
  `auth.json` and optional `config.toml`; other profile state is rejected. Configuration
  is hash-bound and authentication-file identity is metadata-bound without reading the secret.
- Codex version probes and workers receive private `HOME`, `CODEX_SQLITE_HOME`, `TMPDIR`,
  and XDG roots. File-backed credentials are forced, repository `.agents`/`.codex` inputs
  cannot be staged, and the profile is revalidated immediately before every worker spawn.
- The shared capability remains provider-neutral through
  `requires_explicit_execution_profile`; CLI forwarding accepts both split and
  `--flag=value` forms. Documentation records the remaining system-skill and
  credential-read isolation limitations.
- Verification: 19/19 final fake-executor tests, 39/39 focused runtime tests, 373/373
  repository tests, Markdown lint across 84 files, ShellCheck, production JSON parsing,
  Python AST parsing, adapter validate/dry-run, and diff hygiene all pass.
- No real Codex worker or model call ran. The next gate remains a separately approved
  synthetic one-worker smoke, followed by operating-system read-isolation work.

## Dedicated-profile synthetic Codex smoke

### Plan

- [x] Confirm a working Codex binary and validate the one-action synthetic fixture locally.
- [x] Create a disposable owner-only profile without reading or copying authentication contents.
- [x] Materialize mutable probe/worker state in a private operational home, leaving the approval source immutable.
- [x] Create a fresh synthetic workspace and matching session root outside the repository.
- [x] Preview the exact one-worker invocation and inspect its approval boundary.
- [x] Execute exactly one approved worker with the cost-sensitive model mapping.
- [x] Verify the artifact, budget telemetry, profile isolation, and absence of unrelated skill context.
- [x] Record the result and smallest follow-up; do not broaden the executable workflow.

### Guardrails

- One synthetic source file, one reviewer, one provider process, and no retries.
- No repository source is staged or transmitted.
- The dedicated profile contains only `auth.json`; its contents are never printed or copied.
- Stop before execution if preview differs from the expected one-action, concurrency-one boundary.
- Preserve the repository's dirty state and the existing untracked Python cache.

### Review

- First preview found that the desktop Codex binary creates `CODEX_HOME/tmp/arg0`
  package metadata even for `--version`. The subsequent execute failed closed before
  worker launch because the approval source profile had changed. No model call occurred.
- Private operational homes now contain probe/worker scratch state while the validated source
  profile remains unchanged; 21/21 fake-executor tests cover this boundary.
- The one authorized worker reached the provider but failed with `invalid_json_schema` before
  producing an artifact because the output schema used an unsupported regex lookaround.
  Budget telemetry correctly records one provider-process proxy call and zero output.
- The schema now uses a portable, traversal-rejecting path expression, and provider error details
  stay in private logs. A second live provider process requires a fresh explicit approval.
- Operational authentication links are removed on success and failure; the link retained by the
  failed smoke was verified against the source inode and removed without touching the original.
- Verification after the compatibility fixes: 21/21 fake-executor tests, 375/375 repository
  tests, Markdown lint across 84 files, ShellCheck, JSON/Python parsing, and diff hygiene pass.
- The second explicitly approved provider process completed one worker in 3.989 seconds and
  published a valid artifact with no findings. Budget telemetry records one provider-process
  proxy call and 0.050781 KB of validated output.
- The source profile remained minimal and the operational authentication link was removed. The
  short worker log did not name skills, plugins, or `AGENTS.md`, but retained operational state and
  a later offline prompt rendering prove that bundled skills and unrelated desktop orchestration
  instructions were model-visible. This is a concrete material source of the 10,754-token report;
  the exact input/cached/output split was not retained.
- No broader fan-out or additional live worker is appropriate with the desktop runtime.
  Operating-system read isolation remains a separate prerequisite for stronger credential
  confidentiality once a compatible runtime passes offline context attestation.

## Codex usage telemetry attribution

### Plan

- [x] Inventory retained smoke events, logs, prompts, and persisted state without reading credentials.
- [x] Compare the observed evidence with the official `codex exec --json` usage event contract.
- [x] Trace the executor's stdout/stderr handling and current budget telemetry boundary.
- [x] Add a fail-closed, fake-runtime-covered `debug prompt-input` compatibility probe.
- [x] Re-run the compatibility probe immediately before every provider spawn.
- [x] Verify focused tests, the complete suite when code changes, lint, and diff hygiene.
- [x] Record what the 10,754-token figure does and does not prove, plus the next gate.

### Guardrails

- No live Codex worker or provider call.
- Do not read, copy, print, or modify authentication contents.
- Preserve retained smoke evidence and the pre-existing untracked Python cache.
- Keep provider-neutral budget semantics; provider-specific usage stays explicitly identified.

### Investigation result

- The retained worker used human-readable output, so only the aggregate `tokens used 10,754`
  survived. Official JSON mode would provide input, cached-input, output, and reasoning-output
  counters, but finer telemetry would not remove the unwanted context.
- The operational home contains 504 KiB of system skills created when the worker started. An
  offline `codex debug prompt-input` with a fresh empty home and all available related feature
  flags disabled proves that the model-visible request still includes the bundled skill catalog
  and unrelated desktop orchestration instructions.
- The root fix is therefore a pre-provider compatibility attestation, not post-provider token
  accounting. A binary that cannot render a minimal prompt must be rejected before approval or
  worker execution.

### Review

- Preview binds a non-secret attestation summary into approval, and execute recomputes it. Every
  serialized pre-spawn section performs a fresh offline attestation before model-call telemetry is
  incremented or the provider process starts.
- Fake Codex coverage passes 23/23, including preview rejection and contamination introduced after
  the first of multiple serialized workers. The complete logical repository suite passes 377/377;
  two adapter tests initially blocked by the workspace sandbox passed when rerun with their intended
  temporary-directory write access.
- The installed desktop Codex binary fails the real offline preview probe with the expected bundled
  skill-context error. Its temporary authentication hardlink was removed immediately, leaving the
  original owner-only file with one link. No live worker or provider call ran.
- Markdown lint across 84 files, ShellCheck, Python AST parsing, production JSON parsing, and diff
  hygiene pass. The pre-existing untracked Python cache remains untouched.
- A future executable gate requires a standalone or updated Codex binary whose offline model-input
  rendering passes, followed by separately approved smoke validation. JSON usage capture remains a
  useful later observability improvement, not a remedy for injected context.
