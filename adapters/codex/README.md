# Codex runtime adapter

The adapter keeps validation and dry runs inert, and adds an explicitly approved
executor for one bounded workflow: the opening fan-out of Quick peer review.

```bash
adapters/codex/codex-runtime.sh capabilities
adapters/codex/codex-runtime.sh validate shared/runtime/fixtures/peer-review-quick.plan.json
adapters/codex/codex-runtime.sh dry-run shared/runtime/fixtures/peer-review-quick.plan.json
```

## Approved execution

Execution requires a fresh session directory whose final component equals the
plan's `session_id`, an explicit working Codex executable, a dedicated authenticated
`CODEX_HOME`, and an explicit model
mapping for every model class used by the plan:

```bash
export SPECTRA_CODEX_MODEL_STANDARD='<codex-model-id>'

adapters/codex/codex-runtime.sh preview PLAN \
  --workspace-root /absolute/project \
  --session-root /absolute/sessions/peer-review-quick-fixture \
  --codex-bin /absolute/path/to/codex \
  --codex-home /absolute/path/to/dedicated-codex-home

adapters/codex/codex-runtime.sh execute PLAN \
  --workspace-root /absolute/project \
  --session-root /absolute/sessions/peer-review-quick-fixture \
  --codex-bin /absolute/path/to/codex \
  --codex-home /absolute/path/to/dedicated-codex-home \
  --approve 'sha256:<token-from-preview>'
```

`preview` hashes the validated plan, canonical roots, Codex binary and version,
model mapping, schema, persona prompts, declared input manifest, and limits. It
runs only `codex --version`; it does not invoke a model or transmit project data.
`execute` recomputes that token and rejects any change before work begins.

Workers receive private staged copies of only their declared workspace inputs and run
with per-run private `HOME`, `CODEX_SQLITE_HOME`, `TMPDIR`, and XDG roots. User files
discovered through the caller's home and XDG roots are not inherited. The approved source
profile is never passed directly to Codex. Instead, each probe or run gets a private
operational `CODEX_HOME`: authentication is hard-linked without reading or copying its
contents, approved configuration is copied by hash, and Codex-created scratch state remains
inside the disposable run directory. The authentication link is removed as soon as worker
execution ends, including failure paths. The invocation forces file-backed credentials
instead of falling back to the OS keyring.
They run with Codex's read-only sandbox, ephemeral state, ignored user config and
rules, and a strict output schema. The executor validates each result and is the
sole writer of final artifacts and budget telemetry.

The explicit Codex home must be an existing normalized directory owned by the current
user with no group or other permissions. It must contain a nonempty, owner-readable
`auth.json` and may contain one owner-only `config.toml`; every other entry is rejected.
Configuration hashes and authentication-file identity are approval-bound and rechecked
immediately before every worker spawn. The moderator never reads, hashes, copies, or logs
authentication contents. The Codex process necessarily receives the hard-linked credential
in its private operational home, however, and the read-only Codex sandbox is not an OS-level
rule preventing worker tools from reading `auth.json`; use a stronger OS/container boundary
when credential confidentiality from worker subprocesses is required.

## Limits and privacy

- Quick `peer-review` opening phase only; one to four independent reviewers
- At most two concurrent workers; no retries, nested workers, resume, or synthesis
- 2,000 files and 20 MiB of staged inputs; 50 KiB total validated artifacts
- Explicit model-class mapping; the fixture uses `standard`, not `frontier`
- Budget `model_calls` are conservative provider-process proxies. Codex CLI does
  not expose an enforceable internal turn ceiling, so executable plans must use
  `max_turns: 1` and each worker is counted as one bounded provider run.
- Local orchestration and artifact storage, but approved worker calls send the
  staged project content to the configured Codex/OpenAI model service
- The adapter does not enable web search or extra writable directories. It does
  not claim provider-level network isolation beyond the tested CLI sandbox.
- Staging controls which project files Spectra supplies in the worker directory;
  Codex's read-only sandbox prevents writes but is not an OS-level read allowlist.
  A same-user worker may still be able to read other host-readable paths.
- Fake-runtime verification proves the worker does not inherit the caller's
  `$HOME/.agents/skills` or ambient `CODEX_HOME`. Bundled and administrator-installed
  skills and system configuration are outside this profile boundary, and a live synthetic
  smoke is still required before treating the executable path as cost-efficient.

The executor requires Python 3.10+ and is currently Unix-only because it uses
process groups and resource limits for timeout and log cleanup.
