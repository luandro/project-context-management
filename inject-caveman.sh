#!/usr/bin/env bash
# inject-caveman.sh — Append caveman-mode directive to AGENTS.md files
#
# Sources:
#   - https://github.com/TheRealSeanDonahoe/agents-md (AGENTS.md standard)
#   - https://github.com/JuliusBrussee/caveman (caveman token-reduction skill)
#
# Usage:
#   ./inject-caveman.sh [SEARCH_ROOT]
#   ./inject-caveman.sh /home/luandro/Dev
#
# Idempotent: skips files that already contain the marker.
#
# Index:
#   Re-runs discover-agents-md.sh to refresh agents-md-index.log before injecting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_FILE="${SCRIPT_DIR}/agents-md-index.log"

SEARCH_ROOT="${1:-.}"
MARKER="<!-- caveman-directive -->"

CAVEMAN_BLOCK='

'"${MARKER}"'

Terse like caveman. Technical substance exact. Only fluff die.
Drop: articles, filler (just/really/basically), pleasantries, hedging.
Fragments OK. Short synonyms. Code unchanged.
Pattern: [thing] [action] [reason]. [next step].
ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift.
Code/commits/PRs: normal. Off: "stop caveman" @[/] "normal mode".
'

# ── Refresh the shared index ──

echo "[discover] Refreshing index..."
"${SCRIPT_DIR}/discover-agents-md.sh" "$SEARCH_ROOT" >/dev/null

if [[ ! -f "$INDEX_FILE" ]]; then
    echo "[err] Index file not found: $INDEX_FILE" >&2
    exit 1
fi

# ── Read index and inject ──

changed=0
skipped=0
errors=0

while IFS=$'\t' read -r file project_name lines modified; do
    [[ -z "$file" ]] && continue

    if grep -qF "$MARKER" "$file" 2>/dev/null; then
        echo "[skip] $project_name ($file) — already injected"
        skipped=$((skipped + 1))
        continue
    fi

    if printf '%s\n' "$CAVEMAN_BLOCK" >> "$file"; then
        echo "[ok]   $project_name ($file)"
        changed=$((changed + 1))
    else
        echo "[err]  $project_name ($file)" >&2
        errors=$((errors + 1))
    fi
done < "$INDEX_FILE"

echo ""
echo "Done. changed=$changed skipped=$skipped errors=$errors"
