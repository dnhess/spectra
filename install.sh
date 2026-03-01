#!/bin/bash
# Spectra — Symlink Installer
# Creates symlinks in ~/.claude/skills/ pointing to this repository.

SKILLS_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SKILLS_DIR"

ln -sfn "$REPO_DIR/shared" "$SKILLS_DIR/shared"
ln -sfn "$REPO_DIR/deep-design" "$SKILLS_DIR/deep-design"
ln -sfn "$REPO_DIR/decision-board" "$SKILLS_DIR/decision-board"
ln -sfn "$REPO_DIR/code-review" "$SKILLS_DIR/code-review"

echo "Spectra installed. Symlinks created in $SKILLS_DIR"
