#!/usr/bin/env bash
# audit-agents-md.sh — Audit AGENTS.md files against best practices
# via Gemini CLI (or static fallback), produce a task-tracker report.
#
# Sources:
#   - https://agents.md (AGENTS.md open standard)
#   - https://github.com/TheRealSeanDonahoe/agents-md (best-practice template)
#   - https://github.com/google-gemini/gemini-cli (Gemini CLI)
#
# Usage:
#   ./audit-agents-md.sh [--static] [--timeout SECS] [--model MODEL] [--max-files N] [--wait] [SEARCH_ROOT]
#   ./audit-agents-md.sh /home/luandro/Dev
#   ./audit-agents-md.sh --static /home/luandro/Dev        # no LLM, grep-based
#   ./audit-agents-md.sh --timeout 60 /home/luandro/Dev    # per-file timeout
#   ./audit-agents-md.sh --model gemini-2.5-flash /home/luandro/Dev
#   ./audit-agents-md.sh --max-files 5 /home/luandro/Dev   # only audit first 5 files
#   ./audit-agents-md.sh --wait /home/luandro/Dev          # wait for quota reset if exhausted
#
# Modes:
#   --static   Use grep-based static analysis (fast, no API calls, no gemini needed)
#   default    Use Gemini CLI for LLM-powered deep audit (slower, more nuanced)
#
# Requirements (gemini mode):
#   - gemini CLI installed and authenticated
#
# Output:
#   - agents-audit-report-<timestamp>.md  — full audit with task-tracker table
#
# Index:
#   Re-runs discover-agents-md.sh to refresh agents-md-index.log before auditing.

set -euo pipefail

# ── Resolve script directory (shared index lives here) ──

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_FILE="${SCRIPT_DIR}/agents-md-index.log"

# ── Parse args ──

MODE="gemini"
GEMINI_MODEL=""          # auto-detected via codexbar, or fallback
PER_FILE_TIMEOUT=60
KILL_AFTER=10
SEARCH_ROOT="."
MAX_FILES=0  # 0 = all
WAIT_FOR_QUOTA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --static)      MODE="static";          shift ;;
        --timeout)     PER_FILE_TIMEOUT="${2:-60}"; shift 2 ;;
        --model)       GEMINI_MODEL="${2:-}"; shift 2 ;;
        --max-files)   MAX_FILES="${2:-0}"; shift 2 ;;
        --wait)        WAIT_FOR_QUOTA=true; shift ;;
        --help|-h)
            sed -n '2,27p' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)             SEARCH_ROOT="$1"; shift ;;
    esac
done
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
REPORT_FILE="agents-audit-report-${TIMESTAMP}.md"

# ── Best-practices prompt for Gemini (embedded so script is self-contained) ──

AUDIT_PROMPT='You are an AGENTS.md quality auditor. Analyze the AGENTS.md file below against these 10 best-practice criteria. For each criterion, rate PASS or FAIL with a brief reason.

CRITERIA:
1. LENGTH: Under 300 lines total. Over 500 = automatic FAIL. (Ideal: 100-200 lines)
2. PROJECT_CONTEXT: Has a "Project context" or equivalent section with stack, framework, language info.
3. BUILD_COMMANDS: Lists install, build, test, lint commands (even as TODOs).
4. CODE_CONVENTIONS: Documents naming, import style, error handling, or testing patterns.
5. DIRECTORY_LAYOUT: Specifies where source and tests live, and any forbidden areas.
6. NON_NEGOTIABLES: Has explicit rules that override everything (no flattery, no fabrication, touch only what you must).
7. PROJECT_LEARNINGS: Has a section for accumulated corrections / self-improvement.
8. VERIFICATION_LOOP: Requires running tests/linters before claiming done. Goal-driven execution.
9. SURGICAL_CHANGES: Explicit rule against drive-by refactors. Every changed line traces to request.
10. CROSS_TOOL_COMPAT: Mentions symlinks to CLAUDE.md/GEMINI.md, or follows the agents.md open standard format.

OUTPUT FORMAT — respond with EXACTLY this markdown structure, nothing else:

## [PROJECT_NAME]

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | LENGTH | PASS/FAIL | ... |
| 2 | PROJECT_CONTEXT | PASS/FAIL | ... |
| 3 | BUILD_COMMANDS | PASS/FAIL | ... |
| 4 | CODE_CONVENTIONS | PASS/FAIL | ... |
| 5 | DIRECTORY_LAYOUT | PASS/FAIL | ... |
| 6 | NON_NEGOTIABLES | PASS/FAIL | ... |
| 7 | PROJECT_LEARNINGS | PASS/FAIL | ... |
| 8 | VERIFICATION_LOOP | PASS/FAIL | ... |
| 9 | SURGICAL_CHANGES | PASS/FAIL | ... |
| 10 | CROSS_TOOL_COMPAT | PASS/FAIL | ... |

**Score: X/10**
**Priority improvements:** (list the 1-3 most impactful fixes, or "None" if 9-10/10)

---

Here is the AGENTS.md file to audit:

```markdown
'

# ── Helpers ──

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ── Refresh the shared index ──

log "Refreshing index via discover-agents-md.sh"
"${SCRIPT_DIR}/discover-agents-md.sh" "$SEARCH_ROOT" >/dev/null

if [[ ! -f "$INDEX_FILE" ]]; then
    err "Index file not found: $INDEX_FILE"
    exit 1
fi

# ── Read index into parallel arrays ──
# Format: path\tproject\tlines\tmodified

paths=()
names=()

while IFS=$'\t' read -r path name lines modified; do
    [[ -z "$path" ]] && continue
    paths+=("$path")
    names+=("$name")
done < "$INDEX_FILE"

total=${#paths[@]}
log "Loaded $total file(s) from index"

if [[ $total -eq 0 ]]; then
    warn "No AGENTS.md files found. Exiting."
    exit 0
fi

# ── Static analysis (grep-based, no LLM) ──

static_audit() {
    local file="$1"
    local score=0
    local fails=()

    local lines
    lines=$(wc -l < "$file")
    if [[ "$lines" -le 300 ]]; then score=$((score + 1)); else fails+=("LENGTH: ${lines} lines (max 300)"); fi

    if grep -qiE '(project context|## stack|## project|language.*version|framework)' "$file"; then score=$((score + 1)); else fails+=("PROJECT_CONTEXT: no stack/framework info"); fi
    if grep -qiE '(install:|build:|test:|lint:|`.*install`|`.*build`|`.*test`|npm|pnpm|cargo|pip|make)' "$file"; then score=$((score + 1)); else fails+=("BUILD_COMMANDS: no build/test/lint commands"); fi
    if grep -qiE '(convention|naming|import style|code style|formatting|eslint|prettier)' "$file"; then score=$((score + 1)); else fails+=("CODE_CONVENTIONS: no coding conventions"); fi
    if grep -qiE '(source.*lives|tests.*live|layout|directory|src/|lib/|do not modify|forbidden)' "$file"; then score=$((score + 1)); else fails+=("DIRECTORY_LAYOUT: no directory structure info"); fi
    if grep -qiE '(non.negotiable|no flatter|no filler|touch only|never fabricate|do not.*refactor)' "$file"; then score=$((score + 1)); else fails+=("NON_NEGOTIABLES: no explicit override rules"); fi
    if grep -qiE '(project learnings|learnings|corrections|accumulated)' "$file"; then score=$((score + 1)); else fails+=("PROJECT_LEARNINGS: no self-improvement section"); fi
    if grep -qiE '(verification|run.*test|run.*lint|claim.*done|before claiming|plausibility)' "$file"; then score=$((score + 1)); else fails+=("VERIFICATION_LOOP: no verification requirements"); fi
    if grep -qiE '(surgical|drive.by|touch only|changed line|every changed|minimal diff)' "$file"; then score=$((score + 1)); else fails+=("SURGICAL_CHANGES: no anti-refactor rules"); fi
    if grep -qiE '(symlink|CLAUDE\.md|GEMINI\.md|agents\.md standard|cross.tool)' "$file"; then score=$((score + 1)); else fails+=("CROSS_TOOL_COMPAT: no cross-tool compat mention"); fi

    echo "$score"
    for f in "${fails[@]}"; do echo "$f" >&2; done
}

# ── Static report builder ──

build_static_report() {
    local file="$1"
    local project_name="$2"
    local score="$3"
    local fail_lines="$4"

    local criteria_names=("LENGTH" "PROJECT_CONTEXT" "BUILD_COMMANDS" "CODE_CONVENTIONS" "DIRECTORY_LAYOUT" "NON_NEGOTIABLES" "PROJECT_LEARNINGS" "VERIFICATION_LOOP" "SURGICAL_CHANGES" "CROSS_TOOL_COMPAT")

    local grep_patterns=(
        '(project context|## stack|## project|language.*version|framework)'
        '(install:|build:|test:|lint:|`.*install`|`.*build`|`.*test`|npm|pnpm|cargo|pip|make)'
        '(convention|naming|import style|code style|formatting|eslint|prettier)'
        '(source.*lives|tests.*live|layout|directory|src/|lib/|do not modify|forbidden)'
        '(non.negotiable|no flatter|no filler|touch only|never fabricate|do not.*refactor)'
        '(project learnings|learnings|corrections|accumulated)'
        '(verification|run.*test|run.*lint|claim.*done|before claiming|plausibility)'
        '(surgical|drive.by|touch only|changed line|every changed|minimal diff)'
        '(symlink|CLAUDE\.md|GEMINI\.md|agents\.md standard|cross.tool)'
    )

    local lines_count
    lines_count=$(wc -l < "$file")

    {
        echo "## ${project_name}"
        echo ""
        echo "| # | Criterion | Status | Notes |"
        echo "|---|-----------|--------|-------|"

        if [[ "$lines_count" -le 300 ]]; then
            echo "| 1 | LENGTH | PASS | ${lines_count} lines |"
        else
            echo "| 1 | LENGTH | FAIL | ${lines_count} lines (max 300) |"
        fi

        for i in $(seq 0 8); do
            crit_num=$((i + 2))
            name="${criteria_names[$((crit_num - 1))]}"
            pattern="${grep_patterns[$i]}"
            if grep -qiE "$pattern" "$file"; then
                echo "| ${crit_num} | ${name} | PASS | Found |"
            else
                echo "| ${crit_num} | ${name} | FAIL | Missing |"
            fi
        done

        echo ""
        echo "**Score: ${score}/10**"

        if [[ "$score" -lt 8 && -n "$fail_lines" ]]; then
            top3="$(echo "$fail_lines" | head -3 | tr '\n' '; ' | sed 's/; $//')"
            echo "**Priority improvements:** ${top3}"
        else
            echo "**Priority improvements:** None"
        fi

        echo ""
        echo "---"
        echo ""
    }
}

# ── Mode check ──

if [[ "$MODE" == "gemini" ]]; then
    if ! command -v gemini &>/dev/null; then
        warn "gemini CLI not found. Falling back to static mode."
        warn "Install gemini with: npm install -g @google/gemini-cli"
        MODE="static"
    fi
fi

# ── Codexbar model selection (auto-detect available model) ──
# Model tier mapping: primary=gemini-2.5-flash, secondary=gemini-2.5-flash-lite,
#   tertiary=gemini-3.1-flash-lite-preview
# If codexbar is installed, query usage and pick the first tier with capacity.
# If all tiers exhausted: --wait sleeps until soonest reset, otherwise fallback to static.

if [[ "$MODE" == "gemini" && -z "$GEMINI_MODEL" ]]; then
    if command -v codexbar &>/dev/null; then
        log "Checking gemini quota via codexbar..."
        codexbar_stderr="$(mktemp)"
        usage_json="$(codexbar usage --provider gemini --json </dev/null 2>"$codexbar_stderr")" || {
            codexbar_rc=$?
            codexbar_err="$(cat "$codexbar_stderr" 2>/dev/null | head -3 || true)"
            rm -f "$codexbar_stderr"
            warn "codexbar query failed (rc=$codexbar_rc)"
            [[ -n "$codexbar_err" ]] && log "  stderr: $codexbar_err"
        }
        rm -f "$codexbar_stderr" 2>/dev/null || true

        if [[ -n "$usage_json" ]]; then
            # Parse tiers in priority order: primary, secondary, tertiary
            declare -A tier_models=(
                ["primary"]="gemini-2.5-flash"
                ["secondary"]="gemini-2.5-flash-lite"
                ["tertiary"]="gemini-3.1-flash-lite-preview"
            )
            tier_order=("primary" "secondary" "tertiary")

            best_model=""
            soonest_reset_epoch=0
            soonest_reset_desc=""

            for tier in "${tier_order[@]}"; do
                pct=$(echo "$usage_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else [data]):
        t = item.get('usage', {}).get('$tier', {})
        print(t.get('usedPercent', 100))
        break
except: print(100)" 2>/dev/null || echo "100")

                if [[ "$(echo "$pct" | cut -d. -f1)" -lt 100 ]]; then
                    best_model="${tier_models[$tier]}"
                    log "  $tier: ${pct}% used -> available (model: $best_model)"
                    break
            else
                # Track soonest reset
                reset_info=$(echo "$usage_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else [data]):
        t = item.get('usage', {}).get('$tier', {})
        print(t.get('resetsAt', '') + '|' + t.get('resetDescription', ''))
        break
except: print('|')" 2>/dev/null || echo "|")
                    reset_at="${reset_info%%|*}"
                    reset_desc="${reset_info##*|}"
                    log "  $tier: ${pct}% used (exhausted) — $reset_desc"

                    # Convert resetsAt to epoch for comparison
                    if [[ -n "$reset_at" && "$reset_at" != "1970-01-01"* ]]; then
                        reset_epoch=$(date -d "${reset_at}" +%s 2>/dev/null || echo "9999999999")
                        if [[ "$soonest_reset_epoch" -eq 0 || "$(echo "$reset_epoch" | cut -d. -f1)" -lt "$(echo "$soonest_reset_epoch" | cut -d. -f1)" ]]; then
                            soonest_reset_epoch="$reset_epoch"
                            soonest_reset_desc="$reset_desc"
                        fi
                    fi
                fi
            done

            if [[ -n "$best_model" ]]; then
                GEMINI_MODEL="$best_model"
                log "Auto-selected model: $GEMINI_MODEL"
            elif [[ "$WAIT_FOR_QUOTA" == true && "$soonest_reset_epoch" -gt 0 ]]; then
                now_epoch=$(date +%s)
                wait_secs=$(( soonest_reset_epoch - now_epoch ))
                if [[ "$wait_secs" -gt 0 ]]; then
                    wait_mins=$(( wait_secs / 60 ))
                    log "All tiers exhausted. Waiting ${wait_mins}m until quota reset ($soonest_reset_desc)..."
                    sleep "$wait_secs"
                    # After waiting, re-query to pick a model
                    usage_json2="$(codexbar usage --provider gemini --json 2>/dev/null)" || true
                    for tier in "${tier_order[@]}"; do
                        pct2=$(echo "$usage_json2" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else [data]):
        print(item.get('usage', {}).get('$tier', {}).get('usedPercent', 100))
        break
except: print(100)" 2>/dev/null || echo "100")
                        if [[ "$(echo "$pct2" | cut -d. -f1)" -lt 100 ]]; then
                            GEMINI_MODEL="${tier_models[$tier]}"
                            log "After wait, $tier is available. Model: $GEMINI_MODEL"
                            break
                        fi
                    done
                fi
            fi
        fi
        rm -f "$codexbar_stderr" 2>/dev/null || true
    fi

    # Fallback if codexbar not installed or couldn't detect
    if [[ -z "$GEMINI_MODEL" ]]; then
        GEMINI_MODEL="gemini-3.1-flash-lite-preview"
        log "Falling back to default model: $GEMINI_MODEL"
    fi

    log "Using gemini CLI: $(command -v gemini) model=${GEMINI_MODEL} timeout=${PER_FILE_TIMEOUT}s"
fi

if [[ "$MODE" == "static" ]]; then
    log "Using static analysis mode (grep-based, no LLM)"
fi

# ── Write report header ──

cat > "$REPORT_FILE" <<HEREDOC
# AGENTS.md Audit Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Search root:** ${SEARCH_ROOT}
**Files audited:** ${total}
**Mode:** ${MODE}

---

HEREDOC

# ── Audit each file ──

audited=0
errors=0
scores=()
declare -A improvements_map

for i in $(seq 0 $((total - 1))); do
    file="${paths[$i]}"
    project_name="${names[$i]}"

    # Respect --max-files limit
    if [[ "$MAX_FILES" -gt 0 && "$audited" -ge "$MAX_FILES" ]]; then
        log "Reached --max-files limit ($MAX_FILES). Stopping."
        break
    fi

    log "Auditing ($((audited + 1))/$total): $project_name"

    if [[ "$MODE" == "static" ]]; then
        audit_stderr="$(mktemp)"
        score="$(static_audit "$file" "$project_name" 2>"$audit_stderr")" || true
        fail_lines="$(cat "$audit_stderr")"
        rm -f "$audit_stderr"

        if [[ -z "$score" ]]; then
            err "Static audit failed for: $file"
            echo "## ${project_name}" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "**ERROR:** Static audit failed." >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "---" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            errors=$((errors + 1))
            audited=$((audited + 1))
            continue
        fi

        build_static_report "$file" "$project_name" "$score" "$fail_lines" >> "$REPORT_FILE"
        scores+=("${project_name}:${score}")

        if [[ "$score" -lt 8 && -n "$fail_lines" ]]; then
            top3="$(echo "$fail_lines" | head -3 | tr '\n' '; ' | sed 's/; $//')"
            improvements_map["${project_name}"]="${top3}"
        fi

    else
        if ! content="$(cat "$file" 2>/dev/null)"; then
            err "Could not read: $file"
            echo "## ${project_name}" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "**ERROR:** Could not read file." >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "---" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            errors=$((errors + 1))
            audited=$((audited + 1))
            continue
        fi

        full_prompt="${AUDIT_PROMPT}${content}"$'\n```'

        # Use temp files for stdout + stderr to avoid TTY-in-subshell issues
        gemini_stdout="$(mktemp)"
        gemini_stderr="$(mktemp)"
        # Write prompt to file, then pipe via stdin inside script(1) to provide
        # a fake PTY — gemini needs one even in headless mode.
        gemini_prompt_file="$(mktemp)"
        printf '%s\n' "$full_prompt" > "$gemini_prompt_file"
        log "  Running gemini -m ${GEMINI_MODEL} (timeout: ${PER_FILE_TIMEOUT}s)..."
        timeout --kill-after="${KILL_AFTER}" "${PER_FILE_TIMEOUT}" \
            script -q -c "gemini --yolo -o text -m ${GEMINI_MODEL} -e none < '${gemini_prompt_file}'" /dev/null \
            </dev/null >"$gemini_stdout" 2>"$gemini_stderr"
        rm -f "$gemini_prompt_file"
        exit_code=$?
        result="$(cat "$gemini_stdout" 2>/dev/null || true)"
        rm -f "$gemini_stdout"

        if [[ $exit_code -eq 0 && -n "$result" ]]; then
            echo "$result" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"

            if score_line="$(echo "$result" | grep -oP 'Score:\s*\K\d+' | head -1)"; then
                scores+=("${project_name}:${score_line}")
                if imp="$(echo "$result" | sed -n '/Priority improvements/,/^---$/p' | grep -v 'Priority improvements' | grep -v '^---' | grep -v '^$' | head -3 | sed 's/^[0-9]*\.\s*//' | tr '\n' '; ' | sed 's/; $//')"; then
                    improvements_map["${project_name}"]="${imp}"
                fi
            fi
            log "  Done. Score: ${score_line:-unknown}"
            rm -f "$gemini_stderr"
        else
            stderr_content="$(cat "$gemini_stderr" 2>/dev/null || true)"
            rm -f "$gemini_stderr"

            # Check for fatal errors — abort entire gemini run
            if echo "$stderr_content" | grep -qi "quota\|QUOTA_EXHAUSTED\|capacity.*exhausted\|429\|ModelNotFound\|not found.*model\|404"; then
                if echo "$stderr_content" | grep -qi "ModelNotFound\|not found.*model\|404"; then
                    err "Gemini model '${GEMINI_MODEL}' not found. Check model name. Falling back to static."
                else
                    err "Gemini API quota exhausted. Falling back to static for remaining files."
                fi
                echo "## ${project_name}" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
                echo "**ERROR:** Gemini fatal error (quota/model). Falling back to static." >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
                echo "---" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
                errors=$((errors + 1))
                audited=$((audited + 1))

                # Switch to static for remaining files
                MODE="static"
                log "Switching to static mode for remaining $((total - audited)) file(s)"

                # Audit remaining files in static mode
                for j in $(seq $((i + 1)) $((total - 1))); do
                    if [[ "$MAX_FILES" -gt 0 && "$audited" -ge "$MAX_FILES" ]]; then
                        break
                    fi
                    rfile="${paths[$j]}"
                    rname="${names[$j]}"
                    log "Auditing ($((audited + 1))/$total): $rname [static fallback]"

                    audit_stderr2="$(mktemp)"
                    rscore="$(static_audit "$rfile" "$rname" 2>"$audit_stderr2")" || true
                    rfail="$(cat "$audit_stderr2")"
                    rm -f "$audit_stderr2"

                    if [[ -n "$rscore" ]]; then
                        build_static_report "$rfile" "$rname" "$rscore" "$rfail" >> "$REPORT_FILE"
                        scores+=("${rname}:${rscore}")
                        if [[ "$rscore" -lt 8 && -n "$rfail" ]]; then
                            top3f="$(echo "$rfail" | head -3 | tr '\n' '; ' | sed 's/; $//')"
                            improvements_map["${rname}"]="${top3f}"
                        fi
                    fi
                    audited=$((audited + 1))
                done
                break  # exit the main for loop
            fi

            if [[ $exit_code -eq 124 || $exit_code -eq 137 ]]; then
                err "Gemini timed out (${PER_FILE_TIMEOUT}s) for: $project_name (killed after +${KILL_AFTER}s)"
            else
                err "Gemini failed (exit $exit_code) for: $project_name"
            fi
            echo "## ${project_name}" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "**ERROR:** Gemini audit failed or timed out (${PER_FILE_TIMEOUT}s)." >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            echo "---" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            errors=$((errors + 1))
        fi
    fi

    audited=$((audited + 1))
done

# ── Task Tracker Summary ──

{
    echo "---"
    echo ""
    echo "# Task Tracker — Projects Needing Improvement"
    echo ""
    echo "| # | Project | Score | Priority Improvements |"
    echo "|---|---------|-------|-----------------------|"

    task_num=0

    IFS=$'\n' sorted=($(for s in "${scores[@]}"; do echo "$s"; done | sort -t: -k2 -n)); unset IFS

    for entry in "${sorted[@]}"; do
        [[ -z "$entry" ]] && continue
        proj="${entry%%:*}"
        score="${entry##*:}"

        if [[ "$score" -lt 8 ]]; then
            task_num=$((task_num + 1))
            imp="${improvements_map[${proj}]:-See full report above}"
            echo "| ${task_num} | ${proj} | ${score}/10 | ${imp} |"
        fi
    done

    if [[ $task_num -eq 0 ]]; then
        echo "| - | *(all projects score 8+)* | - | No immediate action needed |"
    fi

    echo ""
    echo "---"
    echo ""
    echo "**Summary:** ${audited} audited, ${errors} errors, mode=${MODE}."
    echo "**Report saved to:** \`${REPORT_FILE}\`"
} >> "$REPORT_FILE"

# ── Final output ──

echo ""
log "Audit complete. audited=$audited errors=$errors mode=$MODE"
log "Report saved to: $REPORT_FILE"

echo ""
echo "=== TASK TRACKER ==="
grep -A 100 "Task Tracker" "$REPORT_FILE" | head -60
