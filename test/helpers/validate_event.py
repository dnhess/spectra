#!/usr/bin/env python3
"""Validate a JSON event against the Spectra base event schema.

Usage: python3 validate_event.py '<json-string>'
Exit 0 if valid, exit 1 with error message on stderr.
"""

import json
import re
import sys

KNOWN_TYPES = {
    "session_start",
    "phase_transition",
    "agent_complete",
    "session_complete",
    "session_end",
    "feedback",
    "security_violation",
    "composition_invoked",
    "composition_completed",
    "checkpoint_written",
    "handoff_written",
    # Domain events — deep-design
    "review",
    "specialist_request",
    "topic_created",
    "rebuttal",
    "pass",
    "topic_resolved",
    # Domain events — decision-board
    "stance",
    "challenge",
    "concession",
    # Domain events — code-review
    "recon_complete",
    "research_complete",
}

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.IGNORECASE
)

ISO8601_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
)


def validate(event):
    errors = []

    # Required fields
    for field in ("event_id", "sequence_number", "schema_version", "session_id", "timestamp", "type"):
        if field not in event:
            errors.append(f"missing required field: {field}")

    if errors:
        return errors

    # event_id must be UUID format
    if not UUID_RE.match(str(event["event_id"])):
        errors.append(f"event_id is not valid UUID format: {event['event_id']}")

    # sequence_number must be positive integer
    seq = event["sequence_number"]
    if not isinstance(seq, int) or seq < 1:
        errors.append(f"sequence_number must be a positive integer, got: {seq}")

    # schema_version must be "1.0.0"
    if event["schema_version"] != "1.0.0":
        errors.append(f"schema_version must be '1.0.0', got: {event['schema_version']}")

    # timestamp must be ISO-8601
    if not ISO8601_RE.match(str(event["timestamp"])):
        errors.append(f"timestamp is not ISO-8601 format: {event['timestamp']}")

    # type must be known
    if event["type"] not in KNOWN_TYPES:
        errors.append(f"unknown event type: {event['type']}")

    return errors


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 validate_event.py '<json-string>'", file=sys.stderr)
        sys.exit(1)

    try:
        event = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        print(f"invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    errors = validate(event)
    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
