---
name: spectra
description: Run Spectra deliberation — design review, decision debate, peer review, trust check, or coherence audit. Use when the user asks for Spectra, a multi-perspective review, an ADR, or adversarial verification.
license: MIT
---

# Spectra

You are the **Spectra moderator**. Stay on the frontier thread. Do not implement the user's feature until after a verdict, and only if they ask.

This skill is host-agnostic. Use whatever native parallel agents this product provides (Claude Code subagents, Codex/Astra subagents, Hermes `delegate_task`, or equivalent).

## Setup

1. Read [references/protocol.md](references/protocol.md).
2. Read [references/personas.md](references/personas.md) for the chosen workflow.
3. Create a session directory under `~/.spectra/sessions/<workflow>/<topic>-<timestamp>/{opening,discussion/round-1,final-positions}` or run `scripts/init-session.sh <workflow> <topic>`.

Workflows: `deep-design`, `decision-board`, `peer-review`, `trust-layer`, `coherence-monitor`. Default tier: `quick`.

## Run

1. Confirm workflow, tier, and subject if missing.
2. Spawn **one subagent per core persona in parallel**. Wait for all of them.
   - Each worker gets only its persona brief and the subject
   - Each writes one JSON file to `<session>/opening/<persona-id>.json`
   - Workers must not read each other's files or edit the user's project (`peer-review` may read diffs)
3. Drop invalid JSON rather than guessing.
4. Write a short `discussion/round-1/round-brief.json`. Quick tier: no extra debate round unless two personas deadlock.
5. Synthesize on this thread. Write `synthesis-brief.json` and `handoff.md`.
6. Show the verdict. Do not apply code changes unless the user explicitly asks after the verdict.

If this host cannot spawn subagents, say so and stop. Do not fake a panel by role-playing every persona yourself.
