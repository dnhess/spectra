# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-03-02

### Added

- Round Summarization Protocol in `shared/orchestration.md` — moderator-produced `round-brief.json` replaces raw position injection, converting O(agents^2 x rounds^2) token growth to O(agents x rounds)
- `round-brief.json` artifact in session directory template and phase allowlists
- SQLite hybrid storage foundation (`shared/tools/db-utils.sh`) with sessions table for cross-session metadata queries, WAL mode, and parameterized queries
- Unified output validation pipeline (`shared/tools/validate-output.sh`) with 5-stage validation (size, JSON parse, schema, content sanitize, accept) in warn-only mode
- Validation schemas for all skill phases (`shared/schemas/`) — 6 schema definitions for deep-design and decision-board agent outputs
- Expanded failure mode table in shared orchestration (14 scenarios across 3 severity tiers: P0 session-fatal, P1 degraded, P2 recoverable)
- Write-once enforcement for agent output files with creation timestamp verification
- Schema versioning contract in `shared/event-schemas-base.md` with semantic versioning rules and compatibility guarantees
- SQLite integrity check in `spectra doctor`
- Test suites for db-utils (17 tests), validation pipeline (23 tests), and failure modes (13 tests)
- Context budget monitoring with proxy metrics at every phase transition (measurement-only)
- Emergency shutdown protocol with structured `recovery_state` in both SKILL.md files
- `context_budget_status` and `emergency_checkpoint` event types in shared event schemas
- Quality KPI computation (`completion_rate`, `phase_completion_rate`, `security_violations_count`) for all skills
- Deep-design KPIs: `convergence_rate`, `specialist_utilization`, `escalations_count`
- Decision-board KPIs: `concessions_count`, `consensus_strength`, `rounds_debated`
- `specialist_recommended` event type for deep-design specialist tracking
- Quality KPI population in SQLite sessions table at session end
- `interrupted` quality value for emergency shutdown sessions
- Decision-board `session_end` extensions formally documented in event schemas
- Test suites for context budget (15 tests) and quality KPIs (15 tests)
- Code-review Phase 2 parity: context budget monitoring, quality KPIs, SQLite population, `specialist_recommended` event logging
- Missing code-review event types added to event validator (`finding`, `finding_challenged`, `finding_upheld`, `finding_withdrawn`, `finding_modified`, `finding_merged`)
- Prompt content trust level table and deferral triggers for formal tiering in shared orchestration
- Inline trust-boundary comments at all per-phase template sections across all 3 skills (14 total)

### Changed

- Base agent template: added file-read restriction and WebSearch guidelines with Layer 4 mitigations
- Discussion/debate templates: prior-round agent positions now wrapped in randomized delimiters for intra-session content isolation
- Layer 3 enforcement boundary documented as moderator-enforced via validate-output.sh
- Layer 4 WebSearch scope updated to all agents via base template (skills opt out specific types)
- Synthesis agents: removed direct JSONL log access from doc-revision and adr-writer (rely on synthesis-brief.json)
- Synthesis agents: added explicit write-path constraints to all synthesis agents across all skills
- Skill SKILL.md files now reference shared failure mode table instead of inline recovery descriptions
- Agent output files validated through unified pipeline before event log writes (warn-only in Phase 1)
- `spectra doctor` now checks SQLite database health
- Event schema version bumped from 1.0.0 to 1.1.0 (additive only)
- `session_end` events include optional `quality_kpis` object
- WebSearch Guidelines added to 8 agent prompt templates across all 3 skills (opening, discussion, final position, scout, devil's advocate)
- Deep-design: added `### Final Position Agent Prompt Template` with schema (`final_observations` with `revised` flag + `key_positions`)
- Code-review opening template: added file-read restriction and Prior Session Context placeholder
- Code-review discussion template: added explicit WebSearch prohibition in Rules section
- Code-review manifest: fixed stale `source` to `bash` for jsonl-utils.sh invocation
- Model allocation tables added to deep-design and decision-board; code-review flat table updated to tier-based
- `max_turns` reduced: opening/scout/research 18, discussion 12, final position 12, synthesis 18
- Cost Optimization Strategies section added to code-review (parity with deep-design and decision-board)
- Shared orchestration: added model selection guidance in Agent Spawning section
- Discussion templates updated: deep-design and decision-board use `ROUND-SUMMARY` delimiters instead of `AGENT-POSITIONS`; code-review uses condensed summary within existing `REVIEW-DATA` delimiters
- Cost Optimization Strategies updated to "(active)" status in all 3 skills
- `shared/security.md`: updated intra-session isolation delimiter documentation

## [0.2.2] - 2026-03-01

### Fixed

- Trap collision across install/update where cleanup handlers silently overwrote each other
- Rollback not updating VERSION_FILE, causing `spectra status` to report wrong version
- Shell variable injection into python3 -c strings (defense-in-depth hardening)
- `spectra status` showing misleading "update available" in dev mode
- `spectra unlink` failing with "same file" error when restoring CLI copies

### Changed

- Extracted download-verify-extract into shared `download_and_verify_release()` function, eliminating 3-way duplication
- `spectra link` now symlinks CLI bin files to repo so dev changes are picked up immediately

## [0.2.1] - 2026-03-01

### Added

- Orchestration test suite covering event log integrity, session lifecycle, persona validation, security audit, and manifest operations (102 new tests)
- Python schema validators for event validation (`test/helpers/validate_event.py`) and content sanitization testing (`test/helpers/check_sanitization.py`)
- Orchestration test helpers in `common-setup.bash` for session directories, events, sentinels, locks, checkpoints, handoffs, and manifest entries

## [0.2.0] - 2026-03-01

### Changed

- Simplified all persona files to ~10-15 lines (identity + focus + voice format)
- Removed Red Flags, Natural Collaborators, and boilerplate from all personas
- Updated custom specialist template in deep-design SKILL.md to match simplified format
- Session paths migrated from `~/.claude/{skill}-sessions/` to `~/.spectra/sessions/{skill}/`
- Permission `Bash(python3 -c *)` replaced with `Bash(bash ~/.spectra/bin/json-write.sh *)`
- `install.sh` rewritten from symlink creator to full curl-pipe-bash installer
- Installation uses `~/.spectra/` as home directory with symlinks into `~/.claude/skills/`

### Added

- Bats-based functional test suite for CLI commands (53 tests across help, link/unlink, doctor, status, install, uninstall, rollback, backup, json-write, jsonl-utils, and smoke tests)
- Post-link smoke test (`verify_link_health`) runs automatically after `spectra link` and `spectra install`
- Pre-install validation in `install.sh` (disk space, write permissions, network, python3 version, settings.json)
- ShellCheck in local pre-commit hook for staged shell scripts
- CI job for functional tests (`bats-tests` in lint workflow)
- **Spectra CLI** (`bin/spectra`) — install, update, rollback, uninstall, link, unlink, status, doctor, backup commands
- `bin/json-write.sh` — scoped JSON writer replacing broad `python3 -c *` permission
- `.github/workflows/release.yml` — automated release with SHA-256 checksums
- Curl-based installer (`install.sh` rewrite) with `main()` wrapper and checksum verification
- Atomic swap protocol for safe skill updates with trap-based rollback
- mkdir-based settings.json locking with stale lock detection
- Compare-and-swap settings.json writes to prevent concurrent modification
- Migration compatibility symlinks (`~/.claude/{skill}-sessions/` → `~/.spectra/sessions/{skill}/`)
- CI lint rule for hardcoded `~/.claude/` session paths
- **code-review** skill (v1.0) — multi-perspective code review with 6 core + 6 specialist personas
- Reconnaissance phase with scout + research agents for codebase context and current best practices
- Web Search Security model (Layer 4) in `shared/security.md` — provenance tagging, domain scoping, content isolation, query constraints, two-pass research
- `recon/` directory added to Layer 2 security audit allowlist in `shared/security.md`
- Finding lifecycle state machine with UUID-based IDs (`finding-{uuid4}`) and formal state transitions (open/challenged/upheld/withdrawn/modified)
- Deadlock detection algorithm with per-finding count-based detection and session-level circuit breaker (30% threshold)
- Phase boundary validation at each phase transition in code-review skill
- `code-review` symlink added to `install.sh`
- CEO/Strategist "Hiring Authority" for on-the-fly persona creation when domain gaps exist
- **deep-design** core personas: Technical Writer, End User Advocate
- **deep-design** specialists: Performance/SRE Engineer, Legal/Compliance Generalist
- **decision-board** core persona: End User Advocate
- **decision-board** specialists: Performance/SRE, Legal/Compliance, Technical Writer
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
- **Compaction-resilient state checkpoints** (`shared/orchestration.md`) — `session-state.md` written at phase transitions, enabling moderator recovery after context compaction
- **Session handoff for cross-session continuity** (`shared/orchestration.md`) — `handoff.md` written in Phase 6 with key findings, unresolved items, and follow-up recommendations for future sessions
- **Prior session context injection with per-project task summary** (`shared/orchestration.md`) — loads most recent handoff at session start, surfaces history and unresolved items to agents, capped at 5 most recent sessions per project
- `checkpoint_written` and `handoff_written` event types in `shared/event-schemas-base.md`
- `has_handoff` and `session_dirname` fields on cross-session manifest base schema — `session_dirname` stores leaf directory name only, resolved at read time (nullable for backward compatibility)
- `query-project` command in `jsonl-utils.sh` for filtering manifest entries by project name
- **Persistence Protocol — Phase Integration** (`shared/orchestration.md`) — shared phase integration instructions for all skills, defining when and how to wire checkpoints, handoffs, and prior context loading at standard phase boundaries
- **Content sanitization (Layer 3)** for handoff injection into agent prompts (`shared/security.md`) — scans for prompt injection patterns, two-layer framing with meta-instruction and randomized delimiters
- **Structured degradation ladder** for handoff validation failures (`shared/security.md`) — five failure modes with specific actions and event logging
- `.active-{skill}-session` sentinel file for compaction recovery discovery — JSON file written at session start, deleted at session end, enables session directory rediscovery after context compaction
- Atomic write-to-temp-then-rename for checkpoint and handoff files — prevents corrupted files from interrupted writes
- Checkpoint validation with event log replay fallback — verifies section headers and session ID, falls back to JSONL replay on failure
- Tiered retention model documentation — manifest indefinite, handoffs 180 days, raw session data 30 days (implementation deferred)
- Persistence wiring in both `deep-design/SKILL.md` and `decision-board/SKILL.md` — lightweight references to shared Persistence Protocol with skill-specific overrides
- Context Persistence section in `README.md` and persistence step in `CONTRIBUTING.md` skill creation guide

## [0.1.0] - 2026-02-28

### Added
- **deep-design** skill (v4.0) — multi-perspective design review with 10 core + 8 specialist personas
- **decision-board** skill (v2.0) — structured decision debate with 6 core + 6 specialist personas
- Shared orchestration library — blackboard protocol, event schemas, security model
- `install.sh` — symlink installer for `~/.claude/skills/`
- `jsonl-utils.sh` — JSONL query utility for session event logs
