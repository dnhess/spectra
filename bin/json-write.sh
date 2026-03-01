#!/bin/bash
# json-write.sh — scoped JSON writer for Spectra agent output
# Usage: json-write.sh <output-path> [json-string]
# If json-string omitted, reads from stdin.
# Path constraint: only writes under ~/.spectra/sessions/ or the
# session directory passed via SPECTRA_SESSION_DIR env var.
set -euo pipefail

die() { echo "json-write: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: json-write.sh <output-path> [json-string]"

output_path="$1"
shift

# Read JSON from argument or stdin
if [[ $# -ge 1 ]]; then
  json_data="$1"
else
  json_data="$(cat)"
fi

# Resolve to absolute path
abs_path="$(cd "$(dirname "$output_path")" 2>/dev/null && pwd)/$(basename "$output_path")" \
  || die "parent directory does not exist: $(dirname "$output_path")"

# Path constraint: must be under allowed directories
allowed=false
sessions_dir="$HOME/.spectra/sessions"
if [[ "$abs_path" == "$sessions_dir"/* ]]; then
  allowed=true
fi
# Also allow SPECTRA_SESSION_DIR if set (for deep-design-sessions etc.)
if [[ -n "${SPECTRA_SESSION_DIR:-}" ]] && [[ "$abs_path" == "${SPECTRA_SESSION_DIR}"/* ]]; then
  allowed=true
fi
# Allow ~/.claude/*-sessions/ for backward compatibility
if [[ "$abs_path" == "$HOME/.claude/"*"-sessions/"* ]]; then
  allowed=true
fi

[[ "$allowed" == "true" ]] || die "path not allowed: $output_path (must be under $sessions_dir)"

# Validate JSON
echo "$json_data" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null \
  || die "invalid JSON"

# Atomic write: temp file then mv
tmp_file="${abs_path}.tmp.$$"
echo "$json_data" > "$tmp_file"
mv "$tmp_file" "$abs_path"
