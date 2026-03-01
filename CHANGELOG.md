# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `project` field on cross-session manifest entries for both deep-design and decision-board — captures the working directory basename at invocation time, enabling per-project filtering of session history
- **Cross-session manifest base schema** (`shared/event-schemas-base.md`) — common manifest fields (`session_id`, `timestamp`, `project`, `tier`, `agent_count`, `specialist_count`, `quality`, `duration_seconds`, `feedback_rating`) extracted into shared base; each skill's `event-schemas.md` now defines only domain-specific manifest fields
- **Skill composition protocol** (`shared/composition.md`) — generic protocol enabling any skill to invoke another skill mid-session with sequential composition, user gating, and tier downgrade
- **Inline mini-debate** — deep-design can now invoke decision-board to resolve deadlocked discussion topics via `[d] Deliberate` option at the escalation prompt
- `composition_invoked` and `composition_completed` event types in `shared/event-schemas-base.md`
- `resolved_by` and `composition_id` fields on deep-design `topic_resolved` events
- `compositions_invoked` and `topics_resolved_by_composition` fields on deep-design `session_end` events
- `composition_id` and `parent_session_id` fields on decision-board `session_start` events
- `parent_composition_id` and `parent_session_id` fields on decision-board manifest entries
- Composition input handling in decision-board Phase 1 (reads `composition-request.json` to bootstrap sessions)

## [0.1.0] - 2026-02-28

### Added
- **deep-design** skill (v4.0) — multi-perspective design review with 10 core + 8 specialist personas
- **decision-board** skill (v2.0) — structured decision debate with 6 core + 6 specialist personas
- Shared orchestration library — blackboard protocol, event schemas, security model
- `install.sh` — symlink installer for `~/.claude/skills/`
- `jsonl-utils.sh` — JSONL query utility for session event logs
