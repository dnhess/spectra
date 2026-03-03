# Trust Layer — Domain Event Schemas

These events extend `shared/event-schemas-base.md`. Only trust-layer-specific types are defined here.

## `finding`

Written by each persona agent to their output JSON file. Collected by the moderator and aggregated into `trust-verdict`.

    {
      "event_id": "uuid",
      "sequence_number": 7,
      "schema_version": "1.1.0",
      "type": "finding",
      "timestamp": "ISO-8601",
      "session_id": "trust-layer-{topic}-{timestamp}",
      "agent": "package-validator",
      "severity": "critical | major | minor",
      "layer": "package | intent | security | coherence",
      "finding": "Human-readable description of the issue",
      "evidence": "Specific line, reference, or pattern from the input",
      "action": "Recommended resolution"
    }

## `trust_verdict`

Written by the moderator after all persona findings are collected and aggregated.

    {
      "event_id": "uuid",
      "sequence_number": 12,
      "schema_version": "1.1.0",
      "type": "trust_verdict",
      "timestamp": "ISO-8601",
      "session_id": "trust-layer-{topic}-{timestamp}",
      "verdict": "PASS | WARN | FAIL",
      "trust_score": 85,
      "intent_alignment": "aligned | partial | misaligned | unknown",
      "package_check": "passed | warnings | failed",
      "critical_count": 0,
      "major_count": 2,
      "minor_count": 3,
      "findings_by_layer": {
        "package": 0,
        "intent": 1,
        "security": 1,
        "coherence": 3
      }
    }
