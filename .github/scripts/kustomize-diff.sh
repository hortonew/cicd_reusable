#!/bin/bash
set -euo pipefail

# Kustomize Diff Script
# Generates diffs between base and PR branches
#
# Usage: ./kustomize-diff.sh <environments> [overlays_path]
# Example: ./kustomize-diff.sh "dev staging prod" "configs/k8s/kustomize/overlays"
#
# Expects:
#   - base/ directory with base branch checkout (renamed from main/)
#   - pr/ directory with PR branch checkout
#
# Outputs:
#   - diff_output.md with formatted diff for PR comment

ENVS="$1"
OVERLAYS_PATH="${2:-configs/k8s/kustomize/overlays}"

DIFF=""

for env in $ENVS; do
    echo "Diffing $env..."
    
    # Build Base (check if exists first to handle new environments)
    if [ -d "base/$OVERLAYS_PATH/$env" ]; then
        MAIN_OUTPUT=$(kubectl kustomize "base/$OVERLAYS_PATH/$env" 2>&1 || echo "Error building base")
    else
        MAIN_OUTPUT=""
    fi

    # Build PR (check if exists first to handle deleted environments)
    if [ -d "pr/$OVERLAYS_PATH/$env" ]; then
        PR_OUTPUT=$(kubectl kustomize "pr/$OVERLAYS_PATH/$env" 2>&1 || echo "Error building PR")
    else
        PR_OUTPUT=""
    fi
    
    # Write to temp files for git diff
    if [ -z "$MAIN_OUTPUT" ]; then
        # Empty file if env didn't exist
        : > /tmp/base.yaml
    else
        echo "$MAIN_OUTPUT" > /tmp/base.yaml
    fi

    if [ -z "$PR_OUTPUT" ]; then
        # Empty file if env was deleted
        : > /tmp/pr.yaml
    else
        echo "$PR_OUTPUT" > /tmp/pr.yaml
    fi
    
    ENV_DIFF=$(git diff --no-index --no-color /tmp/base.yaml /tmp/pr.yaml 2>/dev/null | tail -n +5 || true)
    
    if [ -n "$ENV_DIFF" ]; then
        # Count additions and removals
        ADDS=$(echo "$ENV_DIFF" | grep -cE '^\+[^+]' || true)
        DELS=$(echo "$ENV_DIFF" | grep -cE '^-[^-]' || true)
        ADDS=${ADDS:-0}
        DELS=${DELS:-0}
        
        DIFF="$DIFF
<details>
<summary><strong>$env</strong> (+$ADDS, -$DELS)</summary>

\`\`\`diff
$ENV_DIFF
\`\`\`

</details>
"
    else
        DIFF="$DIFF
<details>
<summary><strong>$env</strong> (no changes)</summary>

No changes detected.

</details>
"
    fi
done

# Write output
echo "$DIFF" > diff_output.md
echo "Diff output written to diff_output.md"
