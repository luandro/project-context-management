#!/usr/bin/env bash
# discover-agents-md.sh — Build/update the AGENTS.md index log.
#
# Searches SEARCH_ROOT for all AGENTS.md files and writes a flat index:
#   agents-md-index.log
#
# Format (one entry per line, tab-separated):
#   <absolute_path>\t<project_name>\t<lines>\t<last_modified>
#
# Usage:
#   ./discover-agents-md.sh [SEARCH_ROOT]
#   ./discover-agents-md.sh /home/luandro/Dev
#
# Other scripts source this index instead of running find() themselves.
# To always get a fresh index, scripts call this before reading the log.

set -euo pipefail

SEARCH_ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_FILE="${SCRIPT_DIR}/agents-md-index.log"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ── Discover ──

log "Discovering AGENTS.md files under: $SEARCH_ROOT"

tmp="$(mktemp)"
count=0

while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    abs_path="$(readlink -f "$file" 2>/dev/null || echo "$file")"
    project_name="$(basename "$(dirname "$file")")"
    lines="$(wc -l < "$file")"
    modified="$(stat -c %Y "$file" 2>/dev/null || echo 0)"

    printf '%s\t%s\t%s\t%s\n' "$abs_path" "$project_name" "$lines" "$modified" >> "$tmp"
    count=$((count + 1))
done < <(find "$SEARCH_ROOT" -name "AGENTS.md" -type f 2>/dev/null | sort)

mv "$tmp" "$INDEX_FILE"

log "Index updated: $count file(s) -> $INDEX_FILE"

# ── Print summary ──

echo ""
echo "=== AGENTS.md Index ($count files) ==="
column -t -s $'\t' -N "Path,Project,Lines,Modified" "$INDEX_FILE" 2>/dev/null || cat "$INDEX_FILE"
