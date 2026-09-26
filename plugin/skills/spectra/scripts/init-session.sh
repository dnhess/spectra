#!/usr/bin/env bash
# Create a Spectra session directory. No other Spectra tools required.
set -euo pipefail

skill="${1:-}"
topic="${2:-session}"
if [[ -z "$skill" ]]; then
  echo "Usage: init-session.sh <skill> [topic]" >&2
  exit 1
fi

ts="$(date +%Y%m%dT%H%M%S)"
session_dir="${HOME}/.spectra/sessions/${skill}/${topic}-${ts}"
mkdir -p "$session_dir"/{opening,discussion/round-1,final-positions,workers}
printf '%s\n' '{"steps":[]}' > "$session_dir/plan.json"
printf '%s\n' "$session_dir"
