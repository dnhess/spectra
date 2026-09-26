#!/usr/bin/env bash
# budget-metrics.sh — Atomic moderator-owned Spectra budget telemetry
# Usage: bash budget-metrics.sh <init|record> <session-dir> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_TOOL="$SCRIPT_DIR/budget-metrics.py"

if [[ ! -f "$PYTHON_TOOL" ]]; then
  echo "budget-metrics.py not found: $PYTHON_TOOL" >&2
  exit 1
fi

case "${1:-}" in
  init|record)
    exec python3 "$PYTHON_TOOL" "$@"
    ;;
  *)
    echo "Usage: bash budget-metrics.sh <init|record> <session-dir> [options]" >&2
    exit 1
    ;;
esac
