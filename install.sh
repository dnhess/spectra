#!/bin/bash
# Spectra Installer — curl -fsSL <url> | bash
# All logic inside main() so partial downloads don't execute.
set -euo pipefail

GITHUB_REPO="dnhess/spectra"
SPECTRA_HOME="$HOME/.spectra"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "  $*"; }
success() { echo "  ✓ $*"; }
warn() { echo "  ! $*" >&2; }

detect_checksum_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    die "No SHA-256 tool found (need sha256sum or shasum)"
  fi
}

preflight_checks() {
  # 1. Bash version
  [[ "${BASH_VERSINFO[0]}" -ge 3 ]] || die "Bash >= 3.2 required (found ${BASH_VERSION})"

  # 2. curl
  command -v curl >/dev/null 2>&1 || die "curl is required"

  # 3. Already installed
  if [[ -d "$SPECTRA_HOME" ]]; then
    die "Spectra is already installed at $SPECTRA_HOME. Use 'spectra update' instead."
  fi

  # 4. Disk space (need at least 5MB free in $HOME)
  local avail_kb
  avail_kb=$(df -k "$HOME" | awk 'NR==2{print $4}')
  if [[ "$avail_kb" -lt 5120 ]]; then
    die "Insufficient disk space: ${avail_kb}KB available, need at least 5MB"
  fi

  # 5. Write permissions
  local test_file="$HOME/.spectra-install-test-$$"
  if ! touch "$test_file" 2>/dev/null; then
    die "Cannot write to \$HOME ($HOME)"
  fi
  rm -f "$test_file"

  # 6. Network connectivity
  if ! curl --max-time 5 -fsSL -o /dev/null "https://api.github.com" 2>/dev/null; then
    die "Cannot reach api.github.com — check network connectivity"
  fi

  # 7. python3 version
  if command -v python3 >/dev/null 2>&1; then
    local py_version
    py_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    local py_major py_minor
    py_major="${py_version%%.*}"
    py_minor="${py_version#*.}"
    if [[ "$py_major" -lt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -lt 6 ]]; }; then
      warn "python3 version $py_version detected — Spectra requires >= 3.6"
    fi
  else
    warn "python3 not found — skills require it at runtime"
  fi

  # 8. Existing settings.json
  local settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    if ! python3 -c "import json; json.load(open('$settings_file'))" 2>/dev/null; then
      die "Existing $settings_file is not valid JSON — fix it before installing"
    fi
  fi
}

main() {
  echo ""
  echo "=== Spectra Installer ==="
  echo ""

  preflight_checks
  local checksum_cmd
  checksum_cmd="$(detect_checksum_cmd)"

  # Fetch latest release
  info "Fetching latest release..."
  local release_json
  release_json="$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest")" \
    || die "Failed to fetch release info"

  local tag version
  tag="$(echo "$release_json" | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")"
  version="${tag#v}"
  info "Latest version: $version"

  local tarball_name="spectra-${tag}.tar.gz"

  # Get asset URLs from the same API response
  local tarball_url checksums_url
  tarball_url="$(echo "$release_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a['name'] == '$tarball_name':
        print(a['browser_download_url']); sys.exit(0)
sys.exit(1)
")" || die "Tarball not found in release assets"

  checksums_url="$(echo "$release_json" | python3 -c "
import sys, json
for a in json.load(sys.stdin).get('assets', []):
    if a['name'] == 'checksums.txt':
        print(a['browser_download_url']); sys.exit(0)
sys.exit(1)
")" || die "checksums.txt not found in release assets"

  # Download
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" EXIT

  info "Downloading $tarball_name..."
  curl -fsSL -o "$tmp_dir/$tarball_name" "$tarball_url"
  curl -fsSL -o "$tmp_dir/checksums.txt" "$checksums_url"

  # Verify checksum
  local expected actual
  expected="$(grep "$tarball_name" "$tmp_dir/checksums.txt" | awk '{print $1}')"
  actual="$($checksum_cmd "$tmp_dir/$tarball_name" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    die "Checksum mismatch! Expected: $expected, Got: $actual"
  fi
  success "Checksum verified"

  # Extract
  mkdir -p "$SPECTRA_HOME"/{skills,sessions,backups,bin}
  tar -xzf "$tmp_dir/$tarball_name" -C "$SPECTRA_HOME/skills/"
  success "Extracted skills"

  # Install CLI and json-write.sh
  if [[ -f "$SPECTRA_HOME/skills/bin/spectra" ]]; then
    cp "$SPECTRA_HOME/skills/bin/spectra" "$SPECTRA_HOME/bin/spectra"
    chmod +x "$SPECTRA_HOME/bin/spectra"
  else
    die "CLI script not found in tarball"
  fi
  if [[ -f "$SPECTRA_HOME/skills/bin/json-write.sh" ]]; then
    cp "$SPECTRA_HOME/skills/bin/json-write.sh" "$SPECTRA_HOME/bin/json-write.sh"
    chmod +x "$SPECTRA_HOME/bin/json-write.sh"
  fi
  rm -rf "$SPECTRA_HOME/skills/bin"

  echo "$version" > "$SPECTRA_HOME/version"
  echo "release" > "$SPECTRA_HOME/mode"
  success "Installed version $version"

  # Symlinks into ~/.claude/skills/
  local claude_skills="$HOME/.claude/skills"
  mkdir -p "$claude_skills"
  for skill in shared deep-design decision-board code-review; do
    if [[ -d "$SPECTRA_HOME/skills/$skill" ]]; then
      ln -sfn "$SPECTRA_HOME/skills/$skill" "$claude_skills/$skill"
      success "Linked $skill"
    fi
  done

  # Session directories + compat symlinks
  for skill in deep-design decision-board code-review; do
    mkdir -p "$SPECTRA_HOME/sessions/$skill"
    local old_path="$HOME/.claude/${skill}-sessions"
    if [[ ! -e "$old_path" ]]; then
      ln -sfn "$SPECTRA_HOME/sessions/$skill" "$old_path"
      info "Created compat symlink: ${skill}-sessions"
    fi
  done

  # Configure permissions
  local settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    cp "$settings_file" "$SPECTRA_HOME/backups/settings.json.$(date +%Y%m%d-%H%M%S)"
    success "Backed up settings.json"
  fi

  local current="{}"
  [[ -f "$settings_file" ]] && current="$(cat "$settings_file")"

  local updated
  updated="$(echo "$current" | python3 -c "
import sys, json
settings = json.load(sys.stdin)
spectra_perms = [
    'Bash(mkdir -p ~/.spectra/sessions/*)',
    'Bash(bash ~/.spectra/bin/json-write.sh *)',
    'Bash(bash ~/.claude/skills/shared/tools/jsonl-utils.sh *)',
    'Write(~/.spectra/sessions/**)',
    'Read(~/.spectra/sessions/**)',
    'Glob(~/.spectra/sessions/**)',
    'Write(~/.spectra/.active-*)'
]
perms = settings.get('permissions', {})
allow = perms.get('allow', [])
for p in spectra_perms:
    if p not in allow:
        allow.append(p)
perms['allow'] = allow
settings['permissions'] = perms
json.dump(settings, sys.stdout, indent=2)
print()
")"

  echo "$updated" | python3 -c "import sys, json; json.load(sys.stdin)" \
    || die "Generated invalid settings.json"

  local tmp_settings="$settings_file.tmp.$$"
  echo "$updated" > "$tmp_settings"
  mv "$tmp_settings" "$settings_file"
  success "Permissions configured"

  # PATH
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$SPECTRA_HOME/bin/spectra" "$HOME/.local/bin/spectra"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "\$HOME/.local/bin is not in your PATH"
    info "  Add to your shell profile:"
    info "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  # Cleanup
  rm -rf "$tmp_dir"
  trap - EXIT

  echo ""
  echo "=== Install Complete ==="
  echo ""
  info "Version: $version"
  info "Home:    $SPECTRA_HOME"
  info "Skills:  shared, deep-design, decision-board, code-review"
  echo ""
  info "Run 'spectra status' to verify installation"
  info "Run 'spectra doctor' to check health"
}

# main() is the last callable — bash must parse the entire script first
main
