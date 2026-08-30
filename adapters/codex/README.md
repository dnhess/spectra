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
plan's `session_id`, an explicit working Codex executable, and an explicit model
mapping for every model class used by the plan:

```bash
export SPECTRA_CODEX_MODEL_STANDARD='<codex-model-id>'

adapters/codex/codex-runtime.sh preview PLAN \
  --workspace-root /absolute/project \
  --session-root /absolute/sessions/peer-review-quick-fixture \
  --codex-bin /absolute/path/to/codex

adapters/codex/codex-runtime.sh execute PLAN \
  --workspace-root /absolute/project \
  --session-root /absolute/sessions/peer-review-quick-fixture \
  --codex-bin /absolute/path/to/codex \
  --approve 'sha256:<token-from-preview>'
```

`preview` hashes the validated plan, canonical roots, Codex binary and version,
model mapping, schema, persona prompts, declared input manifest, and limits. It
runs only `codex --version`; it does not invoke a model or transmit project data.
`execute` recomputes that token and rejects any change before work begins.

Workers receive private staged copies of only their declared workspace inputs.
They run with Codex's read-only sandbox, ephemeral state, ignored user config and
rules, and a strict output schema. The executor validates each result and is the
sole writer of final artifacts and budget telemetry.

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
- The desktop Codex runtime can still load descriptions of skills installed in the
  user's Codex home despite ignored user config and disabled skill-search/plugin
  features. This can add a large fixed context cost per worker. Use this executor
  experimentally until a separately authenticated minimal Codex home or an
  equivalent App Server/SDK isolation boundary is available.

The executor requires Python 3.10+ and is currently Unix-only because it uses
process groups and resource limits for timeout and log cleanup.
