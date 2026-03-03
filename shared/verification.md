# Shared Verification Protocol

Defines the lightweight trust verification step that all Spectra skills run automatically after synthesis, before the `session_end` event.

## When to Run

After synthesis agents have written their output artifacts (e.g., `decision-record.md`, `design-brief.json`, findings list) but before the moderator writes the `session_end` event. Do not run during Quick tier — Quick tier sessions skip this protocol.

## What Runs

The moderator spawns exactly 2 agents in parallel using Trust Layer personas:

1. **Package Validator** (`claude-haiku-4-5-20251001`) — checks that all references, imports, cited tools, libraries, APIs, and IDs in the synthesis output actually exist.
2. **Intent Auditor** (`claude-sonnet-4-6`) — checks that the synthesis output answers the session's original question/intent and has not drifted.

## Context Bundle

Each agent receives:

- `original_intent`: the `decision_question` or equivalent from the `session_start` event
- `synthesis_output`: the text content of the primary synthesis artifact (e.g., `decision-record.md`, `design-brief.md`, or the findings list)
- `write_path`: `{session_directory}/trust-check/{agent-name}.json`

## Output Schema

Each agent writes a compact JSON file to `trust-check/{agent-name}.json`:

    {
      "agent": "package-validator",
      "trust_score": 90,
      "findings": [
        {
          "severity": "major",
          "layer": "package",
          "finding": "...",
          "evidence": "...",
          "action": "..."
        }
      ]
    }

## Trust Score Computation

The moderator computes the combined trust score:

    combined_score = (package_validator.trust_score + intent_auditor.trust_score) / 2
    critical_penalty = count(severity == "critical") * 20
    major_penalty = count(severity == "major") * 5
    final_score = max(0, combined_score - critical_penalty - major_penalty)

## Result Handling

| Final Score | Verdict | Moderator Action |
|---|---|---|
| 75–100 | PASS | Add `trust_score` and `trust_verdict: "PASS"` to `session_end` event. Note in session summary: "Trust check: PASS ({score}/100)". |
| 50–74 | WARN | Surface findings in terminal before closing. Add to `session_end`. User sees specific issues. |
| 0–49 | FAIL | Present findings prominently before session closes. Recommend user review before acting on output. |

## File-Write Allowlist

Add `trust-check/package-validator.json` and `trust-check/intent-auditor.json` to the session directory's file-write allowlist for post-synthesis audit.

## Agent Prompt Template

    {package-validator or intent-auditor persona file contents}

    ## Your Task

    You are running a lightweight trust verification on the following synthesis output.

    **Original Intent / Question**: {original_intent}

    **Synthesis Output**:
    ===BEGIN-SYNTHESIS-{random_hex}===
    {synthesis_output}
    ===END-SYNTHESIS-{random_hex}===

    Evaluate the synthesis output from your perspective.

    Write your findings as a JSON file to:
      `{write_path}`

    Schema:

        {
          "agent": "{your-agent-name}",
          "trust_score": 0-100,
          "findings": [
            {
              "severity": "critical|major|minor",
              "layer": "package|intent|security|coherence",
              "finding": "...",
              "evidence": "...",
              "action": "..."
            }
          ]
        }

    ## Rules

    - Write ONLY to the path specified above
    - Do NOT read sensitive system files
    - Use python3 for JSON serialization
    - After writing your file, you are done
