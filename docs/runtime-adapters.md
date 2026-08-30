# Spectra runtime adapters

## Status

This is an additive compatibility slice. The current Claude Code skills remain the
default execution path. The provider-neutral contract and Codex adapter now prove
both inert planning and one deliberately narrow executable workflow: the opening
fan-out of Quick peer review.

Validation, rendering, capability inspection, and dry runs remain local and do not
invoke a model. Executable work is opt-in, requires a digest emitted by `preview`,
and sends only staged declared inputs to the configured Codex model service.

## Architecture

Spectra uses a ports-and-adapters boundary:

```text
Workflow and session core
  graphs, tiers, budgets, quorum, artifacts, verification
                         |
                         v
Versioned runtime plan and capability contracts
                         |
              +----------+----------+
              |                     |
              v                     v
      Claude Code path        Codex adapter
       (existing skills)      (plan + bounded execute)
```

The core describes work using capabilities and model classes. It does not encode
provider-specific model identifiers, tool names, permission modes, or installation
paths. An adapter maps those neutral requirements onto a host runtime.

## Contract principles

- Plans are versioned and validated before rendering or execution.
- Every worker declares its role, phase, dependencies, completion artifact, model
  class, permissions, and budget increments.
- Artifact paths and quorum rules remain identical across adapters.
- Runtime capability documents declare supported operations and limits explicitly.
- Unsupported capabilities cause a clear failure or a declared degradation; they
  never silently broaden permissions.
- Dry runs are deterministic and never invoke a model.

The schemas and Quick peer-review fixture live in `shared/runtime/`.

## Codex spike

The Codex adapter supports:

```text
codex-runtime.sh capabilities
codex-runtime.sh doctor
codex-runtime.sh validate <plan.json>
codex-runtime.sh render <plan.json>
codex-runtime.sh dry-run <plan.json> [--out <result.json>]
codex-runtime.sh preview <plan.json> --workspace-root <absolute-path> \
  --session-root <absolute-path> --codex-bin <absolute-path> --codex-home <absolute-path> [--max-concurrency 1|2]
codex-runtime.sh execute <plan.json> --workspace-root <absolute-path> \
  --session-root <absolute-path> --codex-bin <absolute-path> --codex-home <absolute-path> --approve <sha256-token> \
  [--max-concurrency 1|2]
```

The same commands are exposed through the main CLI:

```text
spectra runtime list
spectra runtime codex capabilities
spectra runtime codex doctor
spectra runtime codex validate <plan.json>
spectra runtime codex render <plan.json>
spectra runtime codex dry-run <plan.json> [--out <result.json>]
spectra runtime codex preview <plan.json> --workspace-root <absolute-path> \
  --session-root <absolute-path> --codex-bin <absolute-path> --codex-home <absolute-path>
spectra runtime codex execute <plan.json> --workspace-root <absolute-path> \
  --session-root <absolute-path> --codex-bin <absolute-path> --codex-home <absolute-path> --approve <sha256-token>
```

`doctor` proves the configured executable can answer `--version`; presence on
`PATH` alone is not considered healthy. It never starts a model call. `dry-run`
returns a normalized execution summary with `project_content_transmitted` set to
`false`.

`preview` requires a dedicated authenticated Codex home and binds the plan, canonical roots, Codex executable and version, explicit
model-class mapping, schema, persona prompts, declared input content hashes, and
executor limits into one approval token. `execute` recomputes the token before
creating budget state or launching workers. Any change invalidates approval.

For the executable slice, each worker receives a private staged snapshot of only
its declared workspace paths. Codex runs read-only and ephemeral, without user
configuration, project rules, web search flags, or extra writable directories.
The executor enforces at most four actions and two concurrent processes, validates
every artifact, and remains the sole final-artifact and budget-metrics writer.
`model_calls` remains a provider-run proxy: Codex CLI does not expose a hard
internal-turn ceiling. Executable plans therefore require `max_turns: 1`, meaning
one bounded `codex exec` process, and cost remains primarily controlled by action,
concurrency, model-class, input-size, output-size, and wall-time limits.

Staging controls which project files Spectra puts in each worker's current
directory. Codex's `read-only` sandbox prevents writes; it is not a filesystem
read allowlist, so this slice does not claim protection from a malicious same-user
worker reading other host-readable paths. Stronger confidentiality needs an
OS/container permission profile. Executable commands require Python 3.10+.

Earlier desktop testing with the ambient user profile added substantial unrelated
skill context before the review input was considered. Preview and execute now require
a separately authenticated, owner-only `CODEX_HOME` containing only required `auth.json`
and optional `config.toml`. Configuration is hashed into approval; authentication-file
identity is bound without the moderator reading, hashing, copying, or logging its contents.
The profile is rechecked immediately before each worker spawn, and file-backed credential
storage is forced so execution cannot fall back to an ambient OS-keyring credential.
The validated source profile is not passed directly to Codex. Each version probe and run
receives a disposable operational `CODEX_HOME` with hard-linked authentication and a
hash-verified configuration copy, keeping Codex-created package and scratch state outside
the approval source. The operational authentication link is removed immediately after all
worker processes finish, including failure paths; it is not retained with session logs.

Workers use per-run private `HOME`, `CODEX_SQLITE_HOME`, `TMPDIR`, and XDG roots;
caller-home and XDG-discovered files are not inherited. This closes the known personal
user-profile discovery paths in fake-runtime tests, but does not suppress system
configuration, bundled or administrator-installed skills, or provide an OS filesystem
read allowlist. Because the Codex process receives a hard link to the file credential in
its operational `CODEX_HOME`, OS-level isolation is still required to prevent a hostile
worker tool from reading it.
Live end-to-end smoke validation therefore remains pending.

Relevant upstream references: [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode),
the [Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables),
the [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference),
and [Codex skill discovery](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).

## MCP boundary

MCP is an optional context and tool boundary for systems such as Slack, Linear,
Drive, browsers, and internal services. It is not Spectra's scheduler or event
store. Spectra continues to use its local session directory and moderator-owned
event trail as the deterministic coordination layer.

## Local versus offline

A local Codex workflow operates against a local workspace, but that is not the same
as offline inference. Planning and orchestration stay local. Approved execution
sends staged inputs to the configured Codex/OpenAI model service. A future
local-process adapter would be required for fully offline inference.

## Next gate

The next gate is a separately approved synthetic one-worker end-to-end smoke using
the dedicated profile, followed by operating-system read isolation tests. Discussion,
synthesis, retries,
dependencies, nested workers, resume, and large fleets remain explicitly
unsupported until this slice produces trustworthy evidence.
