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
- **Testing note:** When running these via a forge agent, append `&!` to disown the agent and prevent `suspended (tty output)` at exit:
  ```bash
  forge &!
  ```
  Or run the scripts directly without an agent wrapper.

### Layout
- `discover-agents-md.sh` — builds/updates `agents-md-index.log` (shared file list)
- `audit-agents-md.sh` — audits AGENTS.md files against 10 best-practice criteria
- `inject-caveman.sh` — appends caveman-mode directive to AGENTS.md files
- `agm-config.json` — config: project dirs, models, harness, audit settings
- `.agm-config.local.json` — local overrides (gitignored), merged on top of defaults
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

1. Generated files (`agents-md-index.log`, `agents-audit-report-*.md`, `.agm-config.local.json`) must be in `.gitignore`
2. `agm-config.json` is the single config source; scripts parse it with `python3 -c "import json"` (already available, no new dependencies)
3. Local overrides go in `.agm-config.local.json` — merged on top of defaults, never committed
4. `discover-agents-md.sh` must produce deterministic output for the same input
5. Consumer scripts must always refresh the index before reading it
