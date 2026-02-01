#!/bin/bash
set -euo pipefail

# Detect Changed Environments Script
# Finds which Kustomize environments are affected by changes
#
# Usage: ./detect-changes.sh <kustomize_root> [base_dir] [overlays_dir] [base_ref]
# Example: ./detect-changes.sh configs/k8s/kustomize base overlays main
#
# Outputs to GITHUB_OUTPUT:
#   - environments: space-separated list of affected environments
#   - changed_files: comma-separated list of changed files

KUSTOMIZE_ROOT="${1:-configs/k8s/kustomize}"
BASE_DIR="${2:-base}"
OVERLAYS_DIR="${3:-overlays}"
BASE_REF="${4:-main}"

# Ensure we have the base ref
git fetch origin "$BASE_REF" --depth=1

# Use --no-renames so that renamed files are reported as add+delete rather than rename
# This ensures deleted environments are properly detected
CHANGED_FILES=$(git diff --no-renames --name-only "origin/$BASE_REF" -- "$KUSTOMIZE_ROOT/")
echo "Changed files:"
echo "$CHANGED_FILES"

# Save changed files list (newline to comma)
CHANGED_FILES_LIST=$(echo "$CHANGED_FILES" | tr '\n' ',' | sed 's/,$//')
echo "changed_files=$CHANGED_FILES_LIST" >> "$GITHUB_OUTPUT"

# Get all environment names from overlays folder (union of PR and Base branches)
# This ensures we catch deleted environments (in Base but not PR) and new environments (in PR but not Base)
PR_ENVS=$(ls -1 "$KUSTOMIZE_ROOT/$OVERLAYS_DIR/" 2>/dev/null || true)

# Normalize path for git ls-tree (remove potential multiple slashes)
GIT_PATH="${KUSTOMIZE_ROOT%/}/${OVERLAYS_DIR%/}"
BASE_ENVS=$(git ls-tree -d --name-only "origin/$BASE_REF:$GIT_PATH" 2>/dev/null | xargs -n 1 basename || true)

ALL_ENVS=$(echo "$PR_ENVS $BASE_ENVS" | tr ' ' '\n' | sort -u | xargs)
echo "Available environments: $ALL_ENVS"

ENVS=""

# If base changed, all environments are affected
if echo "$CHANGED_FILES" | grep -q "$KUSTOMIZE_ROOT/$BASE_DIR/"; then
    ENVS="$ALL_ENVS"
else
    # Check each overlay dynamically
    for env in $ALL_ENVS; do
        if echo "$CHANGED_FILES" | grep -q "$KUSTOMIZE_ROOT/$OVERLAYS_DIR/$env/"; then
            ENVS="$ENVS $env"
        fi
    done
fi

ENVS=$(echo "$ENVS" | xargs)
echo "Environments to diff: $ENVS"
echo "environments=$ENVS" >> "$GITHUB_OUTPUT"
