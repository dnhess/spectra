# Code Review Board Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the code-review skill for Spectra — a multi-perspective code review board using the blackboard architecture.

**Architecture:** New skill directory (`code-review/`) with SKILL.md, event-schemas.md, and 12 persona files. Follows the same patterns as deep-design and decision-board: moderator-driven phases, file-based agent output, JSONL event logging, shared orchestration protocol. Key novelty: a reconnaissance phase (scout + research) with web search security controls.

**Tech Stack:** Markdown (SKILL.md, personas), JSONL event schemas, bash (install.sh), shared orchestration infrastructure.

**Design doc:** `docs/plans/2026-03-01-code-review-board-design.md` (revised post-review)

---

## Dependency Graph

```
Task 1 (scaffold) ─┬─► Task 2 (core personas)
                    ├─► Task 3 (specialist personas)
                    ├─► Task 4 (event schemas)
                    └─► Task 5 (SKILL.md header)
                              │
Task 4 ──────────────────────►├─► Task 6 (SKILL.md recon)
                              ├─► Task 7 (SKILL.md opening)
                              ├─► Task 8 (SKILL.md discussion)
                              ├─► Task 9 (SKILL.md synthesis)
                              └─► Task 10 (SKILL.md infrastructure)
                                        │
Tasks 2-3, 5-10 ───────────────────────►├─► Task 11 (security.md update)
                                        ├─► Task 12 (install.sh + CHANGELOG)
                                        └─► Task 13 (lint + smoke test)
```

Tasks 2, 3, 4 can run in parallel after Task 1.
Tasks 6-10 can run in parallel after Task 5.
Tasks 11-13 are sequential finalization.

---

### Task 1: Scaffold Directory Structure

**Files:**

- Create: `code-review/personas/specialists/` (directory tree)
- Create: `code-review/SKILL.md` (placeholder)
- Create: `code-review/event-schemas.md` (placeholder)

#### Step 1: Create directory structure

```bash
mkdir -p code-review/personas/specialists
touch code-review/SKILL.md
touch code-review/event-schemas.md
```

#### Step 2: Verify structure

```bash
find code-review/ -type f | sort
```

Expected:

```
code-review/event-schemas.md
code-review/SKILL.md
```

#### Step 3: Commit

```bash
git add code-review/
git commit -m "chore: scaffold code-review skill directory structure"
```

---

### Task 2: Write Core Persona Files (6)

**Files:**

- Create: `code-review/personas/design-critic.md`
- Create: `code-review/personas/performance-analyst.md`
- Create: `code-review/personas/reliability-engineer.md`
- Create: `code-review/personas/security-auditor.md`
- Create: `code-review/personas/test-strategist.md`
- Create: `code-review/personas/maintainability-advocate.md`

**Reference:** `deep-design/personas/qa-expert.md` for the simplified format (identity + Focus bullets + Voice). Each persona should be 10-15 lines.

#### Step 1: Write all 6 persona files

Follow this template for each:

```markdown
You are the **{Role}** — {one-line identity}. {one-line personality}.

## Focus

- **{Lens 1}**: {what to look for}?
- **{Lens 2}**: {what to look for}?
- **{Lens 3}**: {what to look for}?
- **{Lens 4}**: {what to look for}?

## Voice

{2-3 sentences describing communication style}. "{example quote}."
```

Persona specifics from design doc:

| Persona | Focus Areas |
|---|---|
| Design Critic | Coupling, cohesion, abstractions, SOLID, naming |
| Performance Analyst | Algorithmic complexity, memory, I/O, caching |
| Reliability Engineer | Error handling, edge cases, failure modes |
| Security Auditor | Input validation, auth, data exposure, injection |
| Test Strategist | Coverage gaps, test quality, edge case testing |
| Maintainability Advocate | Readability, documentation, complexity metrics |

#### Step 2: Verify all files exist and lint passes

```bash
ls code-review/personas/*.md | wc -l  # Should be 6
npm run lint
```

#### Step 3: Commit

```bash
git add code-review/personas/*.md
git commit -m "feat: add 6 core code-review personas"
```

---

### Task 3: Write Specialist Persona Files (6)

**Files:**

- Create: `code-review/personas/specialists/database-expert.md`
- Create: `code-review/personas/specialists/api-designer.md`
- Create: `code-review/personas/specialists/concurrency-expert.md`
- Create: `code-review/personas/specialists/frontend-architect.md`
- Create: `code-review/personas/specialists/infrastructure-reviewer.md`
- Create: `code-review/personas/specialists/accessibility-auditor.md`

#### Step 1: Write all 6 specialist files

Same format as core personas. Specialist trigger conditions from design doc:

| Specialist | Triggered When |
|---|---|
| Database Expert | SQL, ORM code, migrations detected |
| API Designer | HTTP handlers, route definitions, schema files |
| Concurrency Expert | Threads, async/await, locks, channels detected |
| Frontend Architect | React/Vue/Svelte components, CSS, DOM manipulation |
| Infrastructure Reviewer | Dockerfiles, CI configs, IaC templates |
| Accessibility Auditor | HTML, ARIA attributes, UI components |

#### Step 2: Verify and lint

```bash
ls code-review/personas/specialists/*.md | wc -l  # Should be 6
npm run lint
```

#### Step 3: Commit

```bash
git add code-review/personas/specialists/*.md
git commit -m "feat: add 6 specialist code-review personas"
```

---

### Task 4: Write Event Schemas

**Files:**

- Modify: `code-review/event-schemas.md`
- Reference: `deep-design/event-schemas.md` for format
- Reference: `shared/event-schemas-base.md` for base types

#### Step 1: Write event-schemas.md

Follow the exact pattern from `deep-design/event-schemas.md`:

1. Header referencing shared base
2. Each domain event with JSON example
3. `session_start` extensions
4. `session_end` extensions
5. JSONL write semantics (copied from deep-design)
6. Quality computation (adapted for code-review)
7. Cross-session manifest schema with domain-specific fields

Domain events to define (from design doc):

| Event | Phase | Key Fields |
|---|---|---|
| `recon_complete` | Recon | `technologies_detected`, `files_mapped`, `test_coverage_summary` |
| `research_complete` | Recon | `technologies_researched`, `advisories_found`, `deprecations_found` |
| `finding` | Opening | `id`, `severity`, `category`, `file_path`, `line_range`, `description`, `recommendation`, `confidence`, `references` |
| `finding_challenged` | Discussion | `finding_id`, `challenge_type` (false_positive, overstated, missing_context), `argument` |
| `finding_upheld` | Discussion | `finding_id`, `supporting_evidence` |
| `finding_withdrawn` | Discussion | `finding_id`, `reason` |
| `finding_modified` | Discussion | `finding_id`, `original_severity`, `new_severity`, `reason` |
| `finding_merged` | Synthesis | `finding_ids`, `merged_finding_id` |

session_start extensions:

```json
{
  "review_target": "src/auth/service.ts",
  "review_mode": "diff | module",
  "technologies_detected": ["typescript", "express"]
}
```

session_end extensions:

```json
{
  "findings_critical": 3,
  "findings_major": 7,
  "findings_minor": 12,
  "findings_nit": 5,
  "findings_withdrawn": 2,
  "composition_used": false
}
```

Quality computation (code-review specific):

| Quality | Condition |
|---|---|
| Full | All agents completed AND all findings in terminal state (upheld/withdrawn/modified/merged) |
| Partial | At least `ceil(n/2)` agents AND at least 1 finding resolved |
| Minimal | Above quorum (2 agents) but below Partial |

Manifest domain fields (from design doc section "Manifest Entry"):

```json
{
  "review_target": "string",
  "review_mode": "diff | module",
  "technologies_detected": ["string"],
  "findings_critical": 0,
  "findings_major": 0,
  "findings_minor": 0,
  "findings_nit": 0,
  "findings_withdrawn": 0,
  "composition_used": false,
  "feedback_actionable": null
}
```

#### Step 2: Lint

```bash
npm run lint
```

#### Step 3: Commit

```bash
git add code-review/event-schemas.md
git commit -m "feat: add code-review domain event schemas and manifest schema"
```

---

### Task 5: Write SKILL.md — Header, Overview, Compaction Recovery

**Files:**

- Modify: `code-review/SKILL.md`

#### Step 1: Write the YAML frontmatter, overview, and compaction recovery section

The SKILL.md starts with YAML frontmatter (see deep-design pattern):

```yaml
---
name: code-review
description: Use when code needs multi-perspective review before merge. Triggers include PRs, feature branches, module rewrites, or when the user wants to stress-test code quality from every angle. NOT for reviewing documents (use deep-design for that).
---
```

Then write these sections:

1. **Title**: `# Code Review Board v1.0`
2. **Compaction Recovery** (early, survives compaction): Check for `.active-code-review-session`, read `session-state.md`, validate, resume.
3. **Overview**: Blackboard architecture, moderator-driven, file-based coordination. Reference `shared/orchestration.md`.
4. **Success Metrics** table (from design doc).
5. **Input**: Two modes — diff (branch/commit range) and module (file/directory path).
6. **Process**: DOT digraph showing the full flow: Context Prep → Recon (scout + research) → Post-recon gate → Opening Review → Discussion → Final Positions → Synthesis → Cleanup.
7. **Cost Tiers** table (from design doc).
8. **Tier Auto-Selection** criteria (from design doc).
9. **User Journey** (from design doc): slash command, confirmation gate, post-recon gate, discussion controls, feedback.
10. **Security Model**: Reference `shared/security.md`, add Layer 4 (Web Content Isolation) note, document WebSearch constraints.
11. **Content Isolation**: File-path reference default, randomized delimiters for web content.

#### Step 2: Lint

```bash
npm run lint
```

#### Step 3: Commit

```bash
git add code-review/SKILL.md
git commit -m "feat: add code-review SKILL.md header, overview, and user journey"
```

---

### Task 6: Write SKILL.md — Phase 0-1 (Context Prep & Reconnaissance)

**Files:**

- Modify: `code-review/SKILL.md` (append)

#### Step 1: Write Phase 0 (Context Preparation)

Match deep-design's Phase 0 pattern:

- Read `CLAUDE.md` if available
- Detect project type from manifest files
- Query manifest for prior sessions on this project
- Load most recent handoff (with degradation ladder from security.md)
- Build per-project task summary (5 most recent)

#### Step 2: Write Phase 1 (Reconnaissance)

Two steps, following design doc:

**Phase 1, Step 1 — Scout agent:**

- subagent_type: `general-purpose`, mode: `bypassPermissions`, model: `sonnet`
- Read-boundary constraints in prompt: project directory only, no dotfiles, no `.git/`
- Produces: `recon/context-bundle.json`
- Schema matches design doc (structured technology format with name/version/source/confidence)
- Include full agent prompt template
- Polling: Glob for `recon/context-bundle.json`, timeout 60s

**Phase 1, Step 2 — Research agent:**

- subagent_type: `general-purpose`, mode: `bypassPermissions`, model: `sonnet`
- Reads context-bundle technologies, does web searches
- Two-pass pattern: collect then sanitize
- Provenance tagging on all web-sourced content
- Domain scoping in prompt: authoritative docs only
- Produces: `recon/research-brief.json`
- Polling: Glob for `recon/research-brief.json`, timeout 60s
- Skipped for Quick tier

**Phase boundary validation:**

- Validate context-bundle.json: required fields (technologies, files.primary)
- Validate technology names with regex: `^[a-zA-Z0-9._@/-]{1,100}$`
- Strip non-conforming entries before passing to research

**Post-recon checkpoint:**

- Write `session-state.md` after Phase 1
- Write `recon_complete` and `research_complete` events

**Post-recon confirmation gate:**

- Show user: files identified, technologies, conventions, research highlights (Standard/Deep)
- User confirms or adjusts roster before Phase 2

#### Step 3: Lint and commit

```bash
npm run lint
git add code-review/SKILL.md
git commit -m "feat: add code-review Phase 0-1 (context prep and reconnaissance)"
```

---

### Task 7: Write SKILL.md — Phase 2 (Opening Review)

**Files:**

- Modify: `code-review/SKILL.md` (append)

#### Step 1: Write Phase 2

- **Agent selection matrix**: Map personas to review mode (diff vs module) and tier
- **Hard limits**: Quick 3-4, Standard 5-6, Deep 7-8 reviewers. Specialists: Quick 0, Standard 2, Deep 4.
- **Agent spawning**: `general-purpose`, `bypassPermissions`, model `opus`, `max_turns` 25, `run_in_background` true
- **Agent prompt template**: Include persona, project context, context-bundle path, research-brief path, WebSearch constraints, output path and schema
- **Output schema**: Matches design doc reviewer output (finding-{uuid} IDs, severity, category, file_path, line_range, etc.)
- **Polling**: Glob for `opening/*.json`, timeout 120s
- **Quorum**: Minimum 2 agents
- **Specialist recommendations**: Triggered by technology detection from scout. Same pattern as deep-design.
- **Post-phase directory audit**: Check opening/ for expected files only
- **Phase boundary validation**: Validate each reviewer JSON (findings array, required fields on each finding)
- **Topic extraction**: Moderator extracts disagreements into topics for discussion
- **Write events**: `finding` events for each finding, `agent_complete` events, `phase_transition`

#### Step 2: Lint and commit

```bash
npm run lint
git add code-review/SKILL.md
git commit -m "feat: add code-review Phase 2 (opening review)"
```

---

### Task 8: Write SKILL.md — Phase 3 (Discussion)

**Files:**

- Modify: `code-review/SKILL.md` (append)

#### Step 1: Write Phase 3

- **Skip for Quick tier** (0 rounds)
- **Topic extraction**: From opening findings — group by file:line overlap and conflicting severity/recommendations
- **topics.json** schema: Match deep-design pattern but with finding references instead of observation references
- **Discussion agent prompt template**: Fresh agents per round, model `opus`, persona + topics + prior findings + instruction to write `discussion/round-{n}/{agent-name}.json`
- **Output schema**: Array of responses, each with `topic_id`, `type` (finding_challenged/finding_upheld/finding_withdrawn/finding_modified), and substantive content
- **No WebSearch** for discussion agents (security decision)
- **Between-round user prompt**: Enter (continue) / i (dismiss finding as false positive) / w (wrap up)
- **Finding lifecycle state machine**: Document the formal states (open, challenged, upheld, withdrawn, modified) and valid transitions. Only original author can withdraw/modify.
- **Convergence criteria**: Same as deep-design — all topics resolved/deferred, round limit hit, user wraps up, all agents pass
- **Deadlock detection algorithm** (from design doc): Per-finding count-based (2+ cycles), session circuit breaker (30%)
- **Escalation protocol**: Same as deep-design — present positions, user decides
- **Post-phase directory audit**
- **Write events**: `finding_challenged`, `finding_upheld`, `finding_withdrawn`, `finding_modified`, `topic_resolved`

#### Step 2: Lint and commit

```bash
npm run lint
git add code-review/SKILL.md
git commit -m "feat: add code-review Phase 3 (discussion)"
```

---

### Task 9: Write SKILL.md — Phase 4-5 (Final Positions & Synthesis)

**Files:**

- Modify: `code-review/SKILL.md` (append)

#### Step 1: Write Phase 4 (Final Positions)

- **Skip for Quick tier**
- Fresh agents, model `opus`, write to `final-positions/{agent-name}.json`
- Output: Top findings with final severity and confidence after debate
- Polling: Glob, timeout 90s
- Post-phase directory audit
- Write `final_position` events

#### Step 2: Write Phase 5 (Synthesis)

Follow shared orchestration synthesis pipeline:

1. Moderator reads all agent output files
2. Moderator produces `synthesis-brief.json` (same structure as deep-design but with finding-specific fields)
3. Write `session_complete` sentinel to JSONL
4. TeamDelete
5. Spawn standalone synthesis agent (`general-purpose`, `bypassPermissions`, model `sonnet`):
   - Reads synthesis-brief.json + event log
   - Produces `review-findings.md`
   - Output format from design doc: Summary, Critical Findings, Major Findings, Minor Findings, Nits — each with file:line, category, confidence, recommendation, debate notes, references
   - Merge semantics: highest severity wins, all unique recommendations kept, merge noted
6. Post-synthesis directory audit
7. Write `session_end` event

**Quick tier note**: Synthesis reads from `opening/` directly (no `final-positions/`). Output is a prioritized checklist, not full findings doc.

#### Step 3: Lint and commit

```bash
npm run lint
git add code-review/SKILL.md
git commit -m "feat: add code-review Phase 4-5 (final positions and synthesis)"
```

---

### Task 10: Write SKILL.md — Phase 6 & Infrastructure Sections

**Files:**

- Modify: `code-review/SKILL.md` (append)

#### Step 1: Write Phase 6 (Cleanup)

- This phase MUST run even on errors (try/finally)
- Remove `session.lock`
- Write manifest entry to `~/.claude/code-review-sessions/manifest.jsonl`
- Generate `handoff.md` using atomic write (temp-then-rename)
- Write `handoff_written` event
- Delete `.active-code-review-session` sentinel
- Post-review feedback micro-survey
- Stale session detection on next invocation

#### Step 2: Write remaining infrastructure sections

- **Composition**: Deadlock triggers composition with decision-board. Max 1 per session. Full protocol reference to `shared/composition.md`.
- **Web Search Security**: Full section from design doc (provenance, domain scoping, two-pass, query constraints, URL validation)
- **Phase Boundary Validation**: Full table from design doc
- **Finding Lifecycle**: State machine diagram, transition rules, conflict resolution
- **Session State Machine**: COLLECTING → DISCUSSING → CONVERGING → TERMINATED (match deep-design pattern)
- **Hard Resource Limits** table by tier (agents, specialists, rounds, timeouts, quorum)
- **Fault Tolerance**: Agent timeout, quality computation, moderator recovery, try/finally cleanup
- **Dynamic Specialists**: Pre-built check, custom generation template, approval flow
- **File Structure**: Full tree of skill files
- **Deferred to V2**: Items intentionally excluded
- **Unresolved Tensions**: Known limitations

#### Step 3: Lint and commit

```bash
npm run lint
git add code-review/SKILL.md
git commit -m "feat: add code-review Phase 6 and infrastructure sections"
```

---

### Task 11: Update shared/security.md

**Files:**

- Modify: `shared/security.md`

#### Step 1: Add Layer 4 — Web Content Isolation

After the existing Layer 3 (Content Sanitization) section, add a new section:

```markdown
## Layer 4: Web Content Isolation

Applies to skills where agents have WebSearch access (e.g., code-review).

### Provenance Tagging
Web-sourced content must carry `source_url` and `retrieved_at` metadata.
Downstream agents and synthesis must surface provenance to users.

### Domain Scoping
Agent prompts constrain searches to authoritative documentation domains.
Agents are instructed not to follow redirect chains to unknown domains.

### Content Wrapping
Web-sourced content is wrapped in randomized delimiters (same pattern
as Layer 3 content isolation) before injection into downstream prompts.

### Query Constraints
Agents must not include source code, internal identifiers, or session
data in search queries.
```

#### Step 2: Add recon/ to Layer 2 allowlist

In the "Post-Phase Directory Audit" section, add a row to the phase allowlist table:

| Phase | Expected files |
|---|---|
| Recon | `recon/context-bundle.json`, `recon/research-brief.json` |

#### Step 3: Lint and commit

```bash
npm run lint
git add shared/security.md
git commit -m "feat: add Layer 4 (Web Content Isolation) and recon allowlist to security model"
```

---

### Task 12: Update install.sh and CHANGELOG.md

**Files:**

- Modify: `install.sh`
- Modify: `CHANGELOG.md`

#### Step 1: Update install.sh

Add after the decision-board line:

```bash
ln -sfn "$REPO_DIR/code-review" "$SKILLS_DIR/code-review"
```

#### Step 2: Run ShellCheck

```bash
shellcheck install.sh
```

Expected: no errors.

#### Step 3: Update CHANGELOG.md

Add under `## [Unreleased]` → `### Added`:

```markdown
- **code-review** skill (v1.0) — multi-perspective code review with 6 core + 6 specialist personas
- Reconnaissance phase with scout + research agents for codebase context and current best practices
- Web Search Security model (Layer 4) in `shared/security.md` — provenance tagging, domain scoping, content isolation
- `recon/` directory added to Layer 2 security audit allowlist
- Finding lifecycle state machine with UUID-based IDs and formal state transitions
- Deadlock detection algorithm with per-finding count-based detection and session-level circuit breaker
- Phase boundary validation at each phase transition in code-review skill
```

#### Step 4: Lint and commit

```bash
npm run lint
git add install.sh CHANGELOG.md
git commit -m "feat: add code-review to install.sh and update CHANGELOG"
```

---

### Task 13: Lint, Verify, and Smoke Test

**Files:**

- All files created in Tasks 1-12

#### Step 1: Full lint pass

```bash
npm run lint
```

Expected: 0 errors.

#### Step 2: ShellCheck

```bash
shellcheck install.sh
```

#### Step 3: Verify file structure

```bash
find code-review/ -type f | sort
```

Expected:

```
code-review/event-schemas.md
code-review/personas/design-critic.md
code-review/personas/maintainability-advocate.md
code-review/personas/performance-analyst.md
code-review/personas/reliability-engineer.md
code-review/personas/security-auditor.md
code-review/personas/specialists/accessibility-auditor.md
code-review/personas/specialists/api-designer.md
code-review/personas/specialists/concurrency-expert.md
code-review/personas/specialists/database-expert.md
code-review/personas/specialists/frontend-architect.md
code-review/personas/specialists/infrastructure-reviewer.md
code-review/personas/test-strategist.md
code-review/SKILL.md
```

#### Step 4: Verify install.sh works

```bash
bash install.sh
ls -la ~/.claude/skills/code-review
```

Expected: symlink pointing to the repo's `code-review/` directory.

#### Step 5: Verify SKILL.md references are valid

Check that SKILL.md references existing shared files:

```bash
grep -o '~/.claude/skills/shared/[a-z-]*.md' code-review/SKILL.md | sort -u
```

Each referenced file should exist:

```bash
ls ~/.claude/skills/shared/orchestration.md
ls ~/.claude/skills/shared/event-schemas-base.md
ls ~/.claude/skills/shared/security.md
ls ~/.claude/skills/shared/composition.md
```

#### Step 6: Verify event-schemas.md references base correctly

```bash
head -5 code-review/event-schemas.md
```

Should reference `shared/event-schemas-base.md` in the header.

#### Step 7: Verify persona file format

Each persona should have `## Focus` and `## Voice` headers:

```bash
for f in code-review/personas/*.md code-review/personas/specialists/*.md; do
  echo "--- $f ---"
  grep -c "## Focus" "$f"
  grep -c "## Voice" "$f"
done
```

Expected: 1 and 1 for each file.

#### Step 8: Commit verification results

No commit needed — this is a verification task.
