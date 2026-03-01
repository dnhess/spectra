# Shared Orchestration Protocol — Blackboard Architecture

This document defines the reusable orchestration protocol for all multi-agent skills. Each skill's SKILL.md references this file and follows its patterns.

## Architecture

```
Agents ──(Write JSON file)──► Session Directory ◄──(Glob/Read)── Moderator
```

- **Agents** write structured JSON files to designated subdirectories
- **Moderator** (the main Claude instance) polls for file existence using Glob
- **No SendMessage for data exchange** — files are the communication medium
- **Moderator is the sole JSONL event log writer** throughout the entire session

This replaces the hub-and-spoke coordinator pattern. There is no coordinator agent.

## Session Directory Template

Each session creates this directory structure:

```
{sessions_root}/{topic}-{timestamp}/
  session.lock                    # Lock file with TTL
  {event-log}.jsonl               # Moderator-only JSONL event log
  synthesis-brief.json            # Produced by moderator from agent files
  opening/                        # Agent opening-round outputs
    {agent-name}.json
  discussion/                     # Agent discussion responses (per round)
    round-{n}/
      {agent-name}.json
  final-positions/                # Agent final recommendations
    {agent-name}.json
  topics.json                     # Discussion topics (written by moderator)
```

The event log filename is skill-specific (e.g., `review-events.jsonl` for deep-design, `decision-events.jsonl` for decision-board).

## Agent Prompt Template (Base)

Every agent prompt across all skills follows this structure. Skills customize the task-specific sections.

```
{persona file contents}

## Project Context
{CLAUDE.md conventions}
{Detected stack}

## Your Task
{Skill-specific task description}

Write your output as a JSON file to:
  `{session_directory}/{phase_subdir}/{your-agent-name}.json`

Schema:
{Skill-specific JSON schema}

## Rules
- Write ONLY to the path specified above — do not create any other files
- Use python3 for JSON serialization: python3 -c "import json; ..."
- Read the source material at: {source_file_path}
- After writing your file, you are done — do not wait for further instructions
```

### Agent Spawning

All agents are spawned as:
- `subagent_type`: `"general-purpose"`
- `mode`: `"bypassPermissions"` — required for file writes
- `max_turns`: Phase-appropriate limit (typically 15-25 per agent)
- `run_in_background`: `true` — agents run concurrently

For discussion rounds, **spawn fresh agents** rather than reusing previous-round agents. Each round's agents receive:
- The topics they're assigned to (from `topics.json`)
- Relevant positions from other agents (extracted from previous round files)
- Instruction to write to `discussion/round-{n}/{agent-name}.json`

This avoids SendMessage entirely for discussion. More expensive (fresh agent per round) but guaranteed delivery.

## Polling Protocol

The moderator uses Glob to check for agent completion:

```
Glob("{session_dir}/{phase_subdir}/*.json")
```

### Polling Cadence
- Poll every ~10 seconds (interleave with other moderator work between polls)
- Check file count against expected agent count
- When file count matches expected count (or timeout reached), phase is complete

### Timeout Handling
- **Opening round timeout**: 120 seconds (agents should complete in ~60s)
- **Discussion round timeout**: 90 seconds per round
- **Final positions timeout**: 90 seconds
- On timeout: log missing agents as `agent_complete` with status `timeout`, continue if quorum met

### Quorum
- **Minimum 2 agents** must complete for session to proceed
- If quorum not met, session terminates with quality `Minimal`

## JSONL Event Writing

### Single Writer Rule
The moderator is the **sole writer** to the JSONL event log throughout the entire session. There is no writer handoff.

### Write Pattern
```bash
python3 -c "
import json, uuid, datetime, os
events = [
    {
        'event_id': str(uuid.uuid4()),
        'sequence_number': NEXT_SEQ,
        'schema_version': '1.0.0',
        'session_id': 'SESSION_ID',
        'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.') + f'{datetime.datetime.utcnow().microsecond // 1000:03d}Z',
        'type': 'EVENT_TYPE',
        # ... additional fields
    }
]
with open('EVENT_LOG_PATH', 'a') as f:
    for event in events:
        f.write(json.dumps(event) + '\n')
    f.flush()
    os.fsync(f.fileno())
"
```

### Rules
- **Batch writes**: Write multiple events per python3 invocation wherever possible
- **Monotonically increasing** `sequence_number` starting at 1 — no gaps allowed
- **Atomic writes**: Each batch uses `flush()` + `fsync()` for durability
- **JSON serialization**: Always use `json.dumps()` — never string concatenation or echo with interpolation (prevents injection)

### Event Flow
As each agent file is read by the moderator, the moderator writes the corresponding event(s) to the JSONL log. The JSONL log is the structured record; the agent files are the raw data.

## Synthesis Pipeline

After the final phase completes:

1. **Moderator reads all agent output files** from the session directory
2. **Moderator produces `synthesis-brief.json`** — a structured summary for synthesis agents
3. **Moderator writes `session_complete` sentinel** to the JSONL event log
4. **Moderator shuts down the team** (`TeamDelete`)
5. **Moderator spawns 2 parallel standalone synthesis agents** (`mode: "bypassPermissions"`)
   - These are standalone Agent tool invocations, not team members
   - Each produces a specific output artifact (skill-specific)
6. **Post-synthesis directory audit** — moderator verifies no unexpected files appeared

## Fault Tolerance

### Agent Timeout
- Phase-specific timeouts (see Polling Protocol above)
- If an agent file is missing at timeout, moderator writes an `agent_complete` event with `status: "timeout"`
- Session continues if quorum is met

### Quality Computation
Quality is computed deterministically from session outcomes:

| Quality | Condition |
|---|---|
| **Full** | All selected agents completed all phases AND all topics resolved or deferred |
| **Partial** | At least `ceil(n/2)` agents completed AND at least 1 topic resolved |
| **Minimal** | Above quorum (2 agents) but below Partial thresholds |

Where `n` is the number of agents in `session_start.agents`.

### No Heartbeat Monitoring
File-existence polling replaces heartbeat monitoring. There is no coordinator to monitor.

### No Coordinator Failure Mode
With no coordinator, coordinator-failure is eliminated as a failure mode. The moderator (main Claude instance) drives the session directly and cannot "fail" independently.

## Session Lock & Stale Detection

### Lock File Format
```json
{
  "session_id": "skill-topic-timestamp",
  "pid": 12345,
  "started_at": "ISO-8601",
  "ttl_minutes": 30,
  "tier": "standard"
}
```

### TTL by Tier
| Tier | TTL |
|---|---|
| Quick | 15 minutes |
| Standard | 30 minutes |
| Deep | 60 minutes |

### Stale Detection
On invocation, check for existing `session.lock`:
1. If no lock file → proceed normally
2. If lock file exists and TTL has expired → stale session. Log a warning, clean up the lock, proceed.
3. If lock file exists and TTL is active → another session is running. Warn the user and ask whether to continue or abort.

Stale sessions are detected by TTL expiration, not by PID checking (PIDs are unreliable across restarts).

## JSONL Utilities

Use the shared JSONL query utility for reading event data:

```bash
bash ~/.claude/skills/shared/tools/jsonl-utils.sh <command> <file> [args]
```

Commands:
- `read-type <file> <type>` — get all events of a type
- `count <file>` — total event count
- `count-type <file> <type>` — count events of a type
- `last <file>` — last event
- `validate <file>` — validate JSON integrity
- `sequence-check <file>` — verify sequence continuity
- `has-sentinel <file>` — check for `session_complete` event
