# Coherence Monitor — Domain Event Schemas

These events extend `shared/event-schemas-base.md`. Only coherence-monitor-specific types are defined here.

## `coherence_finding`

Written by each persona agent to their output JSON file. Collected by the moderator.

    {
      "event_id": "uuid",
      "sequence_number": 7,
      "schema_version": "1.0.0",
      "type": "coherence_finding",
      "timestamp": "ISO-8601",
      "session_id": "coherence-monitor-{topic}-{timestamp}",
      "agent": "alignment-auditor",
      "severity": "critical | major | minor",
      "dimension": "intent | consistency | constraint | trajectory",
      "finding": "Human-readable description of the coherence issue",
      "evidence": "Specific quote, section reference, or logical chain",
      "course_correction": "Recommended action to restore coherence"
    }

## `coherence_verdict`

Written by the moderator after all findings are aggregated.

    {
      "event_id": "uuid",
      "sequence_number": 14,
      "schema_version": "1.0.0",
      "type": "coherence_verdict",
      "timestamp": "ISO-8601",
      "session_id": "coherence-monitor-{topic}-{timestamp}",
      "verdict": "COHERENT | DRIFTED | CONTRADICTED | CRITICAL",
      "coherence_score": 82,
      "dimensions": {
        "intent_alignment": 90,
        "internal_consistency": 75,
        "constraint_adherence": 85,
        "trajectory_soundness": 78
      },
      "critical_count": 0,
      "major_count": 2,
      "minor_count": 4
    }
