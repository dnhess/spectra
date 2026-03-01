#!/usr/bin/env bash
# validate-output.sh — Unified validation pipeline for agent output files
# Usage: bash validate-output.sh <file> <phase> <skill> [--warn-only]
# No external dependencies beyond python3 (available on macOS and most Linux).
#
# Pipeline stages (in order):
#   1. Size check — file must be <= 50KB
#   2. JSON parse — must be valid JSON; detects truncated JSON as retriable
#   3. Schema validate — checks required fields per phase/skill schema
#   4. Content sanitize — scans for injection patterns
#   5. Accept — all stages passed
#
# Exit codes: 0 (valid), 1 (invalid), 2 (warn-only violation logged but allowed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="${SCHEMAS_DIR:-$SCRIPT_DIR/../schemas}"

MAX_SIZE=51200  # 50KB

usage() {
  cat <<'EOF'
Usage: bash validate-output.sh <file> <phase> <skill> [--warn-only]

Arguments:
  file        Path to the agent output JSON file
  phase       Session phase (opening, discussion, final-positions)
  skill       Skill name (deep-design, decision-board)
  --warn-only Log violations but allow processing (exit 2 instead of 1)

Exit codes:
  0  Valid — all stages passed
  1  Invalid — validation failed
  2  Warn-only — violation logged but allowed
EOF
  exit 1
}

[ $# -lt 3 ] && usage

FILE="$1"
PHASE="$2"
SKILL="$3"
WARN_ONLY=false
if [ "${4:-}" = "--warn-only" ]; then
  WARN_ONLY=true
fi

# Resolve schema file from phase + skill
resolve_schema() {
  local phase="$1" skill="$2"
  local schema_file=""

  case "${phase}:${skill}" in
    opening:deep-design)         schema_file="opening-review.json" ;;
    opening:decision-board)      schema_file="opening-stance.json" ;;
    discussion:deep-design)      schema_file="discussion-rebuttal.json" ;;
    discussion:decision-board)   schema_file="discussion-challenge.json" ;;
    final-positions:deep-design) schema_file="final-position-review.json" ;;
    final-positions:decision-board) schema_file="final-position-debate.json" ;;
    *)
      echo ""
      return 1
      ;;
  esac

  local full_path="$SCHEMAS_DIR/$schema_file"
  if [ ! -f "$full_path" ]; then
    echo ""
    return 1
  fi
  echo "$full_path"
}

# Output a ValidationResult JSON
emit_result() {
  local valid="$1" stage="$2" retriable="$3" size_bytes="$4" agent="$5" phase="$6"
  shift 6
  # Remaining args are error objects as JSON strings
  local errors_json="["
  local first=true
  for err in "$@"; do
    if [ "$first" = true ]; then
      first=false
    else
      errors_json+=","
    fi
    errors_json+="$err"
  done
  errors_json+="]"

  python3 -c "
import json, sys
result = {
    'valid': $valid,
    'stage': '$stage',
    'errors': json.loads(sys.argv[1]),
    'retriable': $retriable,
    'size_bytes': $size_bytes,
    'agent': $agent,
    'phase': '$phase'
}
print(json.dumps(result))
" "$errors_json"
}

make_error() {
  local field="$1" check="$2" message="$3" retriable="$4"
  python3 -c "
import json
err = {
    'field': $([ "$field" = "null" ] && echo "None" || echo "'$field'"),
    'check': '$check',
    'message': '$message',
    'retriable': $retriable
}
print(json.dumps(err))
"
}

# --- Stage 1: Size check ---
if [ ! -f "$FILE" ]; then
  err=$(make_error "null" "file_exists" "File not found" "False")
  emit_result "False" "size_check" "False" "0" "None" "$PHASE" "$err"
  exit 1
fi

FILE_SIZE=$(wc -c < "$FILE" | tr -d ' ')

if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
  err=$(make_error "null" "size_limit" "File exceeds 50KB limit (${FILE_SIZE} bytes)" "False")
  emit_result "False" "size_check" "False" "$FILE_SIZE" "None" "$PHASE" "$err"
  exit 1
fi

# --- Stage 2: JSON parse ---
PARSE_RESULT=$(python3 -c "
import json, sys

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

content_stripped = content.strip()

# Detect truncated JSON: starts with { but does not end with }
if content_stripped.startswith('{') and not content_stripped.endswith('}'):
    print('TRUNCATED')
    sys.exit(0)
if content_stripped.startswith('[') and not content_stripped.endswith(']'):
    print('TRUNCATED')
    sys.exit(0)

try:
    data = json.loads(content_stripped)
    if not isinstance(data, dict):
        print('NOT_OBJECT')
        sys.exit(0)
    print('OK')
except json.JSONDecodeError:
    print('INVALID')
" "$FILE" 2>&1) || true

case "$PARSE_RESULT" in
  TRUNCATED)
    err=$(make_error "null" "json_valid" "Truncated JSON detected" "True")
    emit_result "False" "json_parse" "True" "$FILE_SIZE" "None" "$PHASE" "$err"
    exit 1
    ;;
  INVALID)
    err=$(make_error "null" "json_valid" "Invalid JSON" "False")
    emit_result "False" "json_parse" "False" "$FILE_SIZE" "None" "$PHASE" "$err"
    exit 1
    ;;
  NOT_OBJECT)
    err=$(make_error "null" "json_valid" "JSON must be an object, not an array or primitive" "False")
    emit_result "False" "json_parse" "False" "$FILE_SIZE" "None" "$PHASE" "$err"
    exit 1
    ;;
esac

# Extract agent name from JSON for result metadata
AGENT_NAME=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
agent = data.get('agent')
if agent:
    print(repr(agent))
else:
    print('None')
" "$FILE" 2>/dev/null) || AGENT_NAME="None"

# --- Stage 3: Schema validate ---
SCHEMA_PATH=$(resolve_schema "$PHASE" "$SKILL") || true

if [ -z "$SCHEMA_PATH" ]; then
  err=$(make_error "null" "schema_resolve" "Unknown phase/skill combination: ${PHASE}/${SKILL}" "False")
  emit_result "False" "schema_validate" "False" "$FILE_SIZE" "$AGENT_NAME" "$PHASE" "$err"
  exit 1
fi

SCHEMA_RESULT=$(python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)
with open(sys.argv[2]) as f:
    schema = json.load(f)

errors = []
required = schema.get('required_fields', {})

for field_name, field_type in required.items():
    if field_name not in data:
        errors.append({
            'field': field_name,
            'check': 'required_field',
            'message': f'Missing required field: {field_name}',
            'retriable': False
        })
        continue

    value = data[field_name]

    # nullable type allows None/null
    if field_type == 'nullable':
        continue

    if field_type == 'string' and not isinstance(value, str):
        errors.append({
            'field': field_name,
            'check': 'field_type',
            'message': f'Field {field_name} must be a string, got {type(value).__name__}',
            'retriable': False
        })
    elif field_type == 'number' and not isinstance(value, (int, float)):
        errors.append({
            'field': field_name,
            'check': 'field_type',
            'message': f'Field {field_name} must be a number, got {type(value).__name__}',
            'retriable': False
        })
    elif field_type == 'array' and not isinstance(value, list):
        errors.append({
            'field': field_name,
            'check': 'field_type',
            'message': f'Field {field_name} must be an array, got {type(value).__name__}',
            'retriable': False
        })

if errors:
    print(json.dumps(errors))
else:
    print('OK')
" "$FILE" "$SCHEMA_PATH" 2>&1)

if [ "$SCHEMA_RESULT" != "OK" ]; then
  # SCHEMA_RESULT is a JSON array of errors — pass each element
  ERRORS_ARRAY="$SCHEMA_RESULT"
  python3 -c "
import json, sys

errors = json.loads(sys.argv[1])
agent = $AGENT_NAME
result = {
    'valid': False,
    'stage': 'schema_validate',
    'errors': errors,
    'retriable': False,
    'size_bytes': $FILE_SIZE,
    'agent': agent,
    'phase': '$PHASE'
}
print(json.dumps(result))
" "$ERRORS_ARRAY"
  exit 1
fi

# --- Stage 4: Content sanitize ---
SANITIZE_RESULT=$(python3 -c "
import json, re, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

# Flatten all string values from the JSON for scanning
def extract_strings(obj, prefix=''):
    strings = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            strings.extend(extract_strings(v, f'{prefix}.{k}'))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            strings.extend(extract_strings(v, f'{prefix}[{i}]'))
    elif isinstance(obj, str):
        strings.append((prefix, obj))
    return strings

all_strings = extract_strings(data)
errors = []

# Injection patterns (Layer 3 from security.md)
injection_patterns = [
    (r'(?:^|\s)You are\b', 'system_prompt', 'System prompt fragment: \"You are\"'),
    (r'(?:^|\s)Your role is\b', 'system_prompt', 'System prompt fragment: \"Your role is\"'),
    (r'(?:^|\s)Instructions:', 'system_prompt', 'System prompt fragment: \"Instructions:\"'),
    (r'<tool>', 'tool_invocation', 'Tool invocation pattern: \"<tool>\"'),
    (r'<function_call>', 'tool_invocation', 'Tool invocation pattern: \"<function_call>\"'),
    (r'<invoke>', 'tool_invocation', 'Tool invocation pattern: \"<invoke>\"'),
    (r'(?:^|\s)Ignore previous\b', 'role_redefine', 'Role redefinition: \"Ignore previous\"'),
    (r'(?:^|\s)New instructions\b', 'role_redefine', 'Role redefinition: \"New instructions\"'),
    (r'(?:^|\s)As an AI\b', 'role_redefine', 'Role redefinition: \"As an AI\"'),
]

# Path escape patterns — absolute paths not under ~/.spectra/
path_escape_patterns = [
    (r'/tmp/', 'path_escape', 'Path escape: /tmp/ reference'),
    (r'/etc/', 'path_escape', 'Path escape: /etc/ reference'),
    (r'/var/', 'path_escape', 'Path escape: /var/ reference'),
]

for field_path, text in all_strings:
    for pattern, check, message in injection_patterns:
        if re.search(pattern, text, re.IGNORECASE):
            errors.append({
                'field': field_path.lstrip('.'),
                'check': check,
                'message': message,
                'retriable': False
            })
    for pattern, check, message in path_escape_patterns:
        if re.search(pattern, text):
            errors.append({
                'field': field_path.lstrip('.'),
                'check': check,
                'message': message,
                'retriable': False
            })

if errors:
    print(json.dumps(errors))
else:
    print('OK')
" "$FILE" 2>&1)

if [ "$SANITIZE_RESULT" != "OK" ]; then
  ERRORS_ARRAY="$SANITIZE_RESULT"
  EXIT_CODE=1
  VALID_PY="False"
  if [ "$WARN_ONLY" = true ]; then
    EXIT_CODE=2
    VALID_PY="True"
  fi

  python3 -c "
import json, sys

errors = json.loads(sys.argv[1])
agent = $AGENT_NAME
valid = sys.argv[2] == 'True'
stage = 'content_sanitize' if not valid else 'accepted'
result = {
    'valid': valid,
    'stage': stage,
    'errors': errors,
    'retriable': False,
    'size_bytes': $FILE_SIZE,
    'agent': agent,
    'phase': '$PHASE'
}
print(json.dumps(result))
" "$ERRORS_ARRAY" "$VALID_PY"
  exit "$EXIT_CODE"
fi

# --- Stage 5: Accept ---
emit_result "True" "accepted" "False" "$FILE_SIZE" "$AGENT_NAME" "$PHASE"
exit 0
