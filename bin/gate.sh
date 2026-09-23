#!/usr/bin/env bash
# gate.sh — fail a run when an AGENTS.md constraint is violated.
# Usage: spectra gate [--agents AGENTS.md] [--diff] <path>
# No network. No model call. Literal must-not-contain / must-contain rules only.

set -euo pipefail

usage() {
  echo "Usage: spectra gate [--agents AGENTS.md] [--diff] <path>" >&2
  exit 2
}

agents=""
input=""
is_diff=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents)
      [[ $# -ge 2 ]] || usage
      agents="$2"
      shift 2
      ;;
    --diff)
      is_diff=1
      shift
      ;;
    -h|--help)
      echo "Usage: spectra gate [--agents AGENTS.md] [--diff] <path>"
      echo "Read literal constraints from AGENTS.md and fail the run if the input violates them."
      echo "Exit 0 when every rule passes, 1 on a violation, 2 when no constraints can be enforced."
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "gate: unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$input" ]]; then
        echo "gate: only one input path is supported" >&2
        exit 2
      fi
      input="$1"
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  if [[ -n "$input" ]]; then
    echo "gate: only one input path is supported" >&2
    exit 2
  fi
  input="$1"
fi

[[ -n "$input" ]] || usage

if [[ ! -f "$input" ]]; then
  echo "gate: input not found: $input" >&2
  exit 2
fi

if [[ -z "$agents" ]]; then
  search_dir="$(pwd)"
  if [[ "$is_diff" -eq 0 ]]; then
    search_dir="$(cd "$(dirname "$input")" && pwd)"
  fi
  while true; do
    if [[ -f "$search_dir/AGENTS.md" ]]; then
      agents="$search_dir/AGENTS.md"
      break
    fi
    parent="$(dirname "$search_dir")"
    if [[ "$parent" == "$search_dir" ]]; then
      break
    fi
    search_dir="$parent"
  done
fi

if [[ -z "$agents" || ! -f "$agents" ]]; then
  echo "gate: AGENTS.md not found; refusing to pass without constraints" >&2
  exit 2
fi

# Collect kind<TAB>needle rules.
# A rule counts when it sits in a Constraints heading, or the line is marked
# with "constraint:" and carries must-not-contain: / must-contain:.
rules=()
in_section=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^#{1,6}[[:space:]]+Constraints[[:space:]]*$ ]]; then
    in_section=1
    continue
  fi
  if [[ "$in_section" -eq 1 && "$line" =~ ^#{1,6}[[:space:]]+ ]]; then
    in_section=0
  fi

  marked=0
  if [[ "$line" =~ (^|[[:space:][:punct:]])[Cc]onstraint: ]]; then
    marked=1
  fi
  if [[ "$in_section" -eq 0 && "$marked" -eq 0 ]]; then
    continue
  fi

  kind=""
  needle=""
  if [[ "$line" == *"must-not-contain:"* ]]; then
    kind="must-not-contain"
    needle="${line#*must-not-contain:}"
  elif [[ "$line" == *"must-contain:"* ]]; then
    kind="must-contain"
    needle="${line#*must-contain:}"
  else
    continue
  fi

  needle="${needle#"${needle%%[![:space:]]*}"}"
  needle="${needle%"${needle##*[![:space:]]}"}"
  if [[ "$needle" == *"-->"* ]]; then
    needle="${needle%%-->*}"
    needle="${needle%"${needle##*[![:space:]]}"}"
  fi
  if [[ -z "$needle" ]]; then
    echo "gate: empty constraint in $agents" >&2
    exit 2
  fi
  rules+=("${kind}"$'\t'"${needle}")
done < "$agents"

if [[ ${#rules[@]} -eq 0 ]]; then
  echo "gate: AGENTS.md has no constraints" >&2
  exit 2
fi

failures=0
seen=""

record_failure() {
  local key="$1"
  if [[ -n "$seen" ]] && printf '%s\n' "$seen" | grep -F -x -q -- "$key"; then
    return 0
  fi
  if [[ -n "$seen" ]]; then
    seen="${seen}"$'\n'"${key}"
  else
    seen="$key"
  fi
  printf '%s\n' "$key"
  failures=1
}

check_text_file() {
  local kind="$1" needle="$2" path="$3"
  case "$kind" in
    must-not-contain)
      if grep -F -q -- "$needle" "$path"; then
        record_failure "must-not-contain: ${needle} file=${path}"
      fi
      ;;
    must-contain)
      if ! grep -F -q -- "$needle" "$path"; then
        record_failure "must-contain: ${needle} file=${path}"
      fi
      ;;
    *)
      echo "gate: unrecognized constraint: $kind" >&2
      exit 2
      ;;
  esac
}

# Report each diff hunk (or file header) that contains the forbidden needle.
# must-contain is checked against the whole diff text; a miss names the diff path.
check_diff() {
  local kind="$1" needle="$2" path="$3"
  local line="" file="" hunk=""
  case "$kind" in
    must-contain)
      if ! grep -F -q -- "$needle" "$path"; then
        record_failure "must-contain: ${needle} file=${path}"
      fi
      return 0
      ;;
    must-not-contain) ;;
    *)
      echo "gate: unrecognized constraint: $kind" >&2
      exit 2
      ;;
  esac

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "diff --git "* ]]; then
      file="${line##* b/}"
      hunk=""
    elif [[ "$line" == "+++ "* ]]; then
      file="${line#+++ }"
      file="${file#b/}"
      if [[ "$file" == "/dev/null" ]]; then
        file=""
      fi
    elif [[ "$line" == "@@"* ]]; then
      hunk="${line#@@}"
      hunk="${hunk%%@@*}"
      hunk="@@${hunk}@@"
    fi
    if printf '%s\n' "$line" | grep -F -q -- "$needle"; then
      local where="${file:-$path}"
      if [[ -n "$hunk" ]]; then
        record_failure "must-not-contain: ${needle} file=${where} hunk=${hunk}"
      else
        record_failure "must-not-contain: ${needle} file=${where}"
      fi
    fi
  done < "$path"
}

for rule in "${rules[@]}"; do
  kind="${rule%%$'\t'*}"
  needle="${rule#*$'\t'}"
  if [[ "$is_diff" -eq 1 ]]; then
    check_diff "$kind" "$needle" "$input"
  else
    check_text_file "$kind" "$needle" "$input"
  fi
done

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

printf 'gate: pass\n'
exit 0
