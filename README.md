# Spectra

A **governor plugin** for Codex and Claude. This thread plans and decides.
Cheap subagents do search, tests, and boilerplate. Frontier work waits for
your yes.

It is not a second agent fleet, and it is not a debate panel. If the host
cannot spawn a cheaper worker, Spectra stops. It does not do the grunt work
on the expensive model.

## Install

### Claude Code

```text
/plugin marketplace add dnhess/spectra
/plugin install spectra@spectra
```

Then: `Use Spectra to keep Claude from doing the grep itself.`

### Codex

If this repo is the workspace, enable the Spectra plugin from
`.agents/plugins/marketplace.json`. Or copy `plugin/skills/spectra` to
`~/.agents/skills/spectra` and restart Codex.

Then: `$spectra split this task — cheap workers, ask before frontier.`

No `spectra` CLI. No curl installer. The package is `plugin/`.

## What it does

1. Split the task into `economical`, `standard`, and `frontier` steps.
2. Spawn one cheap subagent per grunt step. Do not inherit this thread's model.
3. Ask before any frontier step. A new frontier step needs a new yes.
4. Join by polling `workers/<id>.json`. Do not wait on chat.
5. Stop if the host cannot pin a cheaper model or cannot spawn.

Workers do not message the governor. If they are stuck they write
`escalate: "frontier"` and stop.

## Why not just ask the host?

Asking Codex or Claude to "be the orchestrator" already works, and it is the
mechanism Spectra uses. It is not a governor.

- Claude Code subagents exist so side work stays out of the main thread, and
  you can pin a cheaper model such as Haiku.
  [Subagents](https://code.claude.com/docs/en/sub-agents).
  Built-in Explore used to run on Haiku. As of v2.1.198 it inherits the main
  conversation's model. Omitting `model` follows Claude's subagent model
  order, which is often the session model.
- Claude agent teams are a different job. Teammates message each other and
  use significantly more tokens than one session. Use subagents for focused
  workers; use teams only when agents must argue with each other.
  [Agent teams](https://code.claude.com/docs/en/agent-teams).
  Spectra does not create a team.
- Codex subagents also exist, including when a skill asks for them. Each
  subagent does its own model and tool work, so the workflow consumes more
  tokens than one agent unless you set a cheaper model. If you do not, the
  subagent inherits the parent model and reasoning effort. Codex currently
  documents `gpt-6-luna` as the faster, lower-cost option for lighter work.
  [Subagents](https://developers.openai.com/codex/subagents).

A prompt that says "delegate" does not pin the model, does not ask before
frontier spend, and does not stop when the host cannot spawn. That contract
is the plugin. A new orchestration runtime would duplicate the host and
spend more.

## What it is not

- Not Claude agent teams, and not a desktop fleet or Kanban.
- Not a judgment panel. Frontier hosts already judge. A persona debate is
  opt-in and spends tokens.
- Not smarter than the model on this thread.

## Opt-in panels

These in-tree skills are for maintainers, and only when you explicitly want
a recorded panel. Do not install them to save money.

- `deep-design` — design review
- `decision-board` — recorded decision
- `peer-review` — multi-perspective code review
- `trust-layer` — adversarial check of AI output
- `coherence-monitor` — drift check on a long session

`install.sh` still links that tree under `~/.claude/skills/`. That is not
the public install.

## Maintainer reference

Prefer the plugin commands above. The CLI prepares a session directory. It
does not run models.

```bash
spectra how
spectra run <skill>
spectra status
spectra update
spectra doctor
```

```bash
curl -fsSL https://raw.githubusercontent.com/dnhess/spectra/main/install.sh | bash
```

That path is only for the original Claude Code skill tree.

### How the fat skills join

The in-tree skills coordinate on a file blackboard. Workers write JSON.
The moderator polls. Workers do not chat. That ledger is the join signal,
not a validator and not the product.

```text
Agents --(write JSON)--> session directory <--(poll)--> moderator
```

Output still goes through the 5-stage check (size, JSON, schema, sanitize,
accept) before the moderator writes the event log. SQLite is scaffolded and
not wired. JSONL is the active log. Budgets are proxy ceilings, not dollar
accounting.

See `shared/orchestration.md` for the fat-skill protocol and
`plugin/skills/spectra/references/protocol.md` for the governor.

### Repository layout

```text
plugin/                  # public install: one Agent Skill
  skills/spectra/        # governor
deep-design/             # opt-in panel
decision-board/
peer-review/
trust-layer/
coherence-monitor/
shared/                  # fat-skill protocol, not a skill
bin/spectra              # maintainer CLI
adapters/codex/          # nested Codex exec stays fail-closed
```

### Recommended permissions

Only for the maintainer CLI install. Add to `~/.claude/settings.json` if you
are not using `install.sh`:

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir -p ~/.spectra/sessions/*)",
      "Bash(bash ~/.spectra/bin/json-write.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/db-utils.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/budget-policy.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/budget-metrics.sh *)",
      "Bash(bash ~/.claude/skills/shared/tools/budget-report.sh *)",
      "Write(~/.spectra/sessions/**)",
      "Read(~/.spectra/sessions/**)",
      "Glob(~/.spectra/sessions/**)",
      "Write(~/.spectra/.active-*)"
    ]
  }
}
```

These are scoped to session directories. They do not grant codebase writes.
