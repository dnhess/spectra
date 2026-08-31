# Codex runtime adapter

The adapter keeps validation and dry runs inert, and adds an explicitly approved
executor for one bounded workflow: the opening fan-out of Quick peer review.

```bash
adapters/codex/codex-runtime.sh capabilities
adapters/codex/codex-runtime.sh validate shared/runtime/fixtures/peer-review-quick.plan.json
adapters/codex/codex-runtime.sh dry-run shared/runtime/fixtures/peer-review-quick.plan.json
adapters/codex/codex-runtime.sh inspect-context --codex-bin /absolute/path/to/codex
```

`inspect-context` is an offline diagnostic. It runs the same isolated local `--version` and
`debug prompt-input` subcommands as preview; Spectra supplies no authentication or project
inputs and invokes no provider subcommand. It reports only message structure, canonicalized byte
counts and SHA-256 fingerprints, envelope-metadata fingerprints, and fixed known system-skill
names. All other observed names are counted and hashed, not shown. Raw prompt
text, metadata values, skill contents, and temporary paths are never emitted. Diagnostic success
does not mean preview would accept the context and cannot authorize execution.

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
runs only local `codex --version` and `codex debug prompt-input` compatibility
probes; neither invokes a model or transmits project data.
`execute` recomputes that token and rejects any change before work begins.

The prompt-context probe uses an empty disposable home, isolated current directory,
disabled optional features, and a sentinel prompt. It accepts only Codex's read-only
permission context, synthetic environment context, the sentinel, and at most one system-skill
manifest matching the adapter's versioned preamble and five-name allowlist. Every referenced
file must be below that disposable home's `skills/.system` directory. The canonicalized manifest
and a descriptor-based, bounded snapshot of every system-skill file and directory are bound into
approval; personal/admin skill paths, malformed manifests, unexpected developer instructions,
and unexpected user content fail preview. The same compatibility snapshot runs immediately
before every provider spawn.

This is a predictive check performed by a separate local `debug prompt-input` process, not an
attestation of the exact later provider request. The executor terminates the probe process group
before snapshotting and rechecks immediately before spawn, but exact request attestation requires
upstream Codex support. No provider call is allowed when the compatibility snapshot fails.

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
  not claim provider-level network isolation beyond the tested CLI sandbox. A same-user
  Codex binary retains host-readable filesystem, keychain, and network capabilities;
  these guarantees rely on expected Codex debug semantics.
- Staging controls which project files Spectra supplies in the worker directory;
  Codex's read-only sandbox prevents writes but is not an OS-level read allowlist.
  A same-user worker may still be able to read other host-readable paths.
- Fake-runtime verification proves the worker does not inherit the caller's
  `$HOME/.agents/skills` or ambient `CODEX_HOME`. Bundled and administrator-installed
  skills and system configuration are outside this profile boundary. One live synthetic worker
  completed without naming them in its short log, but Codex reported 10,754 tokens for the
  36-byte input. Retained state and an offline prompt rendering then proved that the desktop
  runtime included bundled skills and unrelated orchestration instructions in model-visible
  context. The executor now rejects that runtime before approval or provider execution.

The executor requires Python 3.10+ and is currently Unix-only because it uses
process groups and resource limits for timeout and log cleanup.
