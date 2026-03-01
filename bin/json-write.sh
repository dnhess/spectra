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

# Resolve to absolute physical path (pwd -P resolves symlinks)
if ! parent_dir="$(cd "$(dirname "$output_path")" 2>/dev/null && pwd -P)"; then
  die "parent directory does not exist: $(dirname "$output_path")"
fi
abs_path="${parent_dir}/$(basename "$output_path")"

# Path constraint: must be under allowed directories
allowed=false

# Primary: ~/.spectra/sessions/ (resolved physically)
if sessions_dir="$(cd "$HOME/.spectra/sessions" 2>/dev/null && pwd -P)"; then
  if [[ "$abs_path" == "$sessions_dir"/* ]]; then
    allowed=true
  fi
fi

# SPECTRA_SESSION_DIR if set — must itself be under ~/.spectra/ or ~/.claude/
if [[ -n "${SPECTRA_SESSION_DIR:-}" ]]; then
  if resolved_session_dir="$(cd "${SPECTRA_SESSION_DIR}" 2>/dev/null && pwd -P)"; then
    if [[ "$resolved_session_dir" == "$HOME/.spectra/"* ]] || \
       [[ "$resolved_session_dir" == "$HOME/.claude/"* ]]; then
      if [[ "$abs_path" == "$resolved_session_dir"/* ]]; then
        allowed=true
      fi
    fi
  fi
fi

# Backward compatibility: ~/.claude/*-sessions/
if [[ "$abs_path" == "$HOME/.claude/"*"-sessions/"* ]]; then
  allowed=true
fi

[[ "$allowed" == "true" ]] || die "path not allowed: $output_path (must be under ~/.spectra/sessions/)"

# Validate JSON
printf '%s' "$json_data" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null \
  || die "invalid JSON"

# Atomic write: temp file then mv
tmp_file="${abs_path}.tmp.$$"
trap 'rm -f "$tmp_file"' EXIT INT TERM
printf '%s\n' "$json_data" > "$tmp_file"
mv "$tmp_file" "$abs_path"
trap - EXIT INT TERM
