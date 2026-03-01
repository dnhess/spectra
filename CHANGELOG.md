# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Simplified all persona files to ~10-15 lines (identity + focus + voice format)
- Removed Red Flags, Natural Collaborators, and boilerplate from all personas
- Updated custom specialist template in deep-design SKILL.md to match simplified format

### Added

- CEO/Strategist "Hiring Authority" for on-the-fly persona creation when domain gaps exist
- **deep-design** core personas: Technical Writer, End User Advocate
- **deep-design** specialists: Performance/SRE Engineer, Legal/Compliance Generalist
- **decision-board** core persona: End User Advocate
- **decision-board** specialists: Performance/SRE, Legal/Compliance, Technical Writer

## [0.1.0] - 2026-02-28

### Added
- **deep-design** skill (v4.0) — multi-perspective design review with 10 core + 8 specialist personas
- **decision-board** skill (v2.0) — structured decision debate with 6 core + 6 specialist personas
- Shared orchestration library — blackboard protocol, event schemas, security model
- `install.sh` — symlink installer for `~/.claude/skills/`
- `jsonl-utils.sh` — JSONL query utility for session event logs
