#!/bin/bash
# Test shim for spectra CLI — stubs out network calls
# Source this instead of bin/spectra to run commands without network access.
#
# Env vars that control stubs:
#   SPECTRA_TEST_TAG        — tag returned by get_release_tag (e.g., "v0.3.0")
#   SPECTRA_TEST_TARBALL    — path to a pre-built tarball
#   SPECTRA_TEST_CHECKSUMS  — path to a matching checksums.txt

SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SHIM_DIR/../.." && pwd)"

# Source the real CLI to get all functions and constants
# We need to prevent main() from running, so we redefine it before sourcing.
# Strategy: source everything, override the network functions, then call main.

# Step 1: Source the CLI but trap the main call
_original_main_args=("$@")

# Temporarily replace main so sourcing doesn't execute it
eval "$(sed 's/^main "$@"/# main "$@" — disabled by shim/' "$PROJECT_ROOT/bin/spectra")"

# Step 2: Override network functions with test stubs

fetch_latest_release() {
  # Return a fake JSON release payload
  local tag="${SPECTRA_TEST_TAG:-v0.0.0}"
  local tarball_name="spectra-${tag}.tar.gz"
  cat <<RELEASE_JSON
{
  "tag_name": "$tag",
  "assets": [
    {
      "name": "$tarball_name",
      "browser_download_url": "file://${SPECTRA_TEST_TARBALL:-/dev/null}"
    },
    {
      "name": "checksums.txt",
      "browser_download_url": "file://${SPECTRA_TEST_CHECKSUMS:-/dev/null}"
    }
  ]
}
RELEASE_JSON
}

get_release_tag() {
  local release_json="$1"
  echo "$release_json" | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])"
}

get_release_asset_url() {
  local release_json="$1"
  local asset_name="$2"
  echo "$release_json" | ASSET_NAME="$asset_name" python3 -c "
import sys, json, os
release = json.load(sys.stdin)
for asset in release.get('assets', []):
    if asset['name'] == os.environ['ASSET_NAME']:
        print(asset['browser_download_url'])
        sys.exit(0)
print('', end='')
sys.exit(1)
"
}

# Override curl to copy local files instead of fetching URLs
curl() {
  local output_file=""
  local url=""
  local args=("$@")
  local i=0

  # Parse curl-like args to find -o <file> and the URL
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      -o)
        i=$((i + 1))
        output_file="${args[$i]}"
        ;;
      -*)
        # skip other flags (e.g., -fsSL)
        ;;
      *)
        url="${args[$i]}"
        ;;
    esac
    i=$((i + 1))
  done

  if [[ -n "$output_file" && -n "$url" ]]; then
    # Strip file:// prefix if present
    local source="${url#file://}"
    cp "$source" "$output_file"
  fi
}

# Step 3: Run main with the original arguments
main "${_original_main_args[@]}"
