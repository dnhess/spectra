#!/usr/bin/env bash
# budget-policy.sh — Deterministic budget policy wrapper
# Usage: bash budget-policy.sh <command> [args...]
# No external dependencies beyond python3.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_TOOL="$SCRIPT_DIR/budget-policy.py"
POLICY_CATALOG="$SCRIPT_DIR/../schemas/budget-policies.json"

usage() {
  cat <<'EOF'
Usage: bash budget-policy.sh <command> [args...]

Commands:
  defaults <skill> <tier>
  estimate <skill> <tier> [core] [specialists] [rounds]
  evaluate <policy-file> <metrics-file>
  check <policy-file> <metrics-file> [--add-agent-spawns N] [--add-model-calls N] [--add-rounds N] [--phase NAME]
EOF
  exit 1
}

[ $# -lt 1 ] && usage

if [ ! -f "$PYTHON_TOOL" ]; then
  echo "budget-policy.py not found: $PYTHON_TOOL" >&2
  exit 1
fi

if [ ! -f "$POLICY_CATALOG" ]; then
  echo "budget-policies.json not found: $POLICY_CATALOG" >&2
  exit 1
fi

case "$1" in
  defaults|estimate)
    exec python3 "$PYTHON_TOOL" "$1" --policies "$POLICY_CATALOG" "${@:2}"
    ;;
  evaluate|check)
    exec python3 "$PYTHON_TOOL" "$@"
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    ;;
esac
