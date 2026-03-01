#!/usr/bin/env bash
# jsonl-utils.sh — JSONL query utility for skill session event logs
# Usage: bash jsonl-utils.sh <command> <jsonl-file> [args...]
# No external dependencies beyond python3 (available on macOS and most Linux).

set -euo pipefail

JSONL_FILE="${2:-}"

usage() {
  cat <<'EOF'
Usage: bash jsonl-utils.sh <command> <jsonl-file> [args...]

Commands:
  read-type <file> <type>       Print all events of the given type
  count <file>                  Print total event count
  count-type <file> <type>      Print count of events of the given type
  last <file>                   Print the last event
  validate <file>               Validate every line is valid JSON; exit 1 on failure
  sequence-check <file>         Verify sequence_numbers are monotonically increasing with no gaps
  has-sentinel <file>           Exit 0 if session_complete event exists, exit 1 otherwise
  query-project <file> <project>  Print all entries matching the given project name
EOF
  exit 1
}

[ $# -lt 2 ] && usage
COMMAND="$1"

case "$COMMAND" in
  read-type)
    TYPE="${3:?Missing type argument}"
    python3 -c "
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    evt = json.loads(line)
    if evt.get('type') == sys.argv[2]:
        print(json.dumps(evt))
" "$JSONL_FILE" "$TYPE"
    ;;

  count)
    python3 -c "
import sys
count = 0
for line in open(sys.argv[1]):
    if line.strip(): count += 1
print(count)
" "$JSONL_FILE"
    ;;

  count-type)
    TYPE="${3:?Missing type argument}"
    python3 -c "
import json, sys
count = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    evt = json.loads(line)
    if evt.get('type') == sys.argv[2]: count += 1
print(count)
" "$JSONL_FILE" "$TYPE"
    ;;

  last)
    python3 -c "
import sys
last = None
for line in open(sys.argv[1]):
    if line.strip(): last = line.strip()
if last: print(last)
else: sys.exit(1)
" "$JSONL_FILE"
    ;;

  validate)
    python3 -c "
import json, sys
errors = []
for i, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line: continue
    try:
        json.loads(line)
    except json.JSONDecodeError as e:
        errors.append(f'Line {i}: {e}')
if errors:
    for e in errors: print(e, file=sys.stderr)
    sys.exit(1)
print('OK')
" "$JSONL_FILE"
    ;;

  sequence-check)
    python3 -c "
import json, sys
prev = 0
for i, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line: continue
    evt = json.loads(line)
    seq = evt.get('sequence_number')
    if seq is None:
        print(f'Line {i}: missing sequence_number', file=sys.stderr)
        sys.exit(1)
    if seq != prev + 1:
        print(f'Line {i}: expected sequence_number {prev + 1}, got {seq}', file=sys.stderr)
        sys.exit(1)
    prev = seq
print(f'OK — {prev} events, sequence continuous')
" "$JSONL_FILE"
    ;;

  has-sentinel)
    python3 -c "
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    evt = json.loads(line)
    if evt.get('type') == 'session_complete':
        sys.exit(0)
sys.exit(1)
" "$JSONL_FILE"
    ;;

  query-project)
    PROJECT="${3:?Missing project argument}"
    python3 -c "
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    evt = json.loads(line)
    if evt.get('project') == sys.argv[2]:
        print(json.dumps(evt))
" "$JSONL_FILE" "$PROJECT"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    ;;
esac
