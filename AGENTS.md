# AGENTS.md

Drop-in operating instructions for coding agents working on this project.

## Project context

### Stack
- Language: Bash (POSISH-compatible, targets bash 4+)
- No dependencies beyond coreutils, find, grep, sed, wc, stat
- Optional: gemini CLI (`@google/gemini-cli`) for LLM-powered audits

### Commands
- Syntax check: `bash -n <script>.sh`
- Discover: `./discover-agents-md.sh /path/to/search`
- Audit (static): `./audit-agents-md.sh --static /path/to/search`
- Audit (gemini): `./audit-agents-md.sh /path/to/search`
- Inject caveman: `./inject-caveman.sh /path/to/search`

### Layout
- `discover-agents-md.sh` — builds/updates `agents-md-index.log` (shared file list)
- `audit-agents-md.sh` — audits AGENTS.md files against 10 best-practice criteria
- `inject-caveman.sh` — appends caveman-mode directive to AGENTS.md files
- `agents-md-index.log` — generated index (tab-separated: path, project, lines, modified)
- `agents-audit-report-*.md` — generated audit reports

### Conventions
- All scripts use `set -euo pipefail`
- Tab-separated index format: `path\tproject_name\tlines\tmodified_epoch`
- Scripts resolve their own directory via `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
- Index file lives in `SCRIPT_DIR` so all sibling scripts share it
- Every consumer script calls `discover-agents-md.sh` first to refresh the index

### Forbidden
- Do not modify `agents-md-index.log` or `agents-audit-report-*.md` directly — they are generated
- Do not add runtime dependencies beyond bash and coreutils
- Do not remove the `--static` fallback from `audit-agents-md.sh`

## Non-negotiables

1. Generated files (`agents-md-index.log`, `agents-audit-report-*.md`) must be in `.gitignore`
2. All scripts must remain self-contained — no external config files required
3. `discover-agents-md.sh` must produce deterministic output for the same input
4. Consumer scripts must always refresh the index before reading it
