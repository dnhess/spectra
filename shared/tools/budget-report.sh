#!/usr/bin/env bash
# budget-report.sh — Local session budget summaries and aggregate reports
# Usage: bash budget-report.sh <summarize|report|calibrate> [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_TOOL="$SCRIPT_DIR/budget-report.py"

if [[ ! -f "$PYTHON_TOOL" ]]; then
  echo "budget-report.py not found: $PYTHON_TOOL" >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: bash budget-report.sh <summarize|report|calibrate> <session-path> [args...]" >&2
  exit 1
fi

SESSIONS_ROOT="${SPECTRA_SESSION_ROOT:-$HOME/.spectra/sessions}"
if ! RESOLVED_ROOT="$(cd "$SESSIONS_ROOT" 2>/dev/null && pwd -P)"; then
  echo "Spectra sessions root not found: $SESSIONS_ROOT" >&2
  exit 1
fi
if ! RESOLVED_TARGET="$(cd "$2" 2>/dev/null && pwd -P)"; then
  echo "Session path not found: $2" >&2
  exit 1
fi
case "$RESOLVED_TARGET" in
  "$RESOLVED_ROOT"|"$RESOLVED_ROOT"/*) ;;
  *)
    echo "Session path is outside the Spectra sessions root: $2" >&2
    exit 1
    ;;
esac

case "${1:-}" in
  summarize|report|calibrate)
    exec python3 "$PYTHON_TOOL" "$@"
    ;;
  *)
    echo "Usage: bash budget-report.sh <summarize|report|calibrate> [args...]" >&2
    exit 1
    ;;
esac
