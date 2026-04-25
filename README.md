# project-context-management

Bash toolkit for discovering, auditing, and improving `AGENTS.md` files across your projects.

Uses the [agents.md](https://agents.md) open standard and best practices from [Sean Donahoe's AGENTS.md template](https://github.com/TheRealSeanDonahoe/agents-md).

## Scripts

### `discover-agents-md.sh` — Build the index

Searches a directory tree for all `AGENTS.md` files and writes a shared index log.

```bash
./discover-agents-md.sh /home/user/Dev
```

Output: `agents-md-index.log` (tab-separated: path, project name, lines, modified epoch)

### `audit-agents-md.sh` — Audit against best practices

Audits every `AGENTS.md` against 10 criteria and produces a markdown report with a task-tracker table of projects needing improvement.

```bash
# Fast grep-based analysis (no API calls)
./audit-agents-md.sh --static /home/user/Dev

# LLM-powered via Gemini CLI (more nuanced)
./audit-agents-md.sh /home/user/Dev

# Custom per-file timeout (default: 120s)
./audit-agents-md.sh --timeout 60 /home/user/Dev
```

#### 10 audit criteria

| # | Criterion | What it checks |
|---|-----------|---------------|
| 1 | LENGTH | Under 300 lines (ideal 100-200) |
| 2 | PROJECT_CONTEXT | Stack, framework, language info |
| 3 | BUILD_COMMANDS | Install, build, test, lint commands |
| 4 | CODE_CONVENTIONS | Naming, style, patterns |
| 5 | DIRECTORY_LAYOUT | Source/test dirs, forbidden areas |
| 6 | NON_NEGOTIABLES | Override rules (no flattery, no fabrication) |
| 7 | PROJECT_LEARNINGS | Self-improvement section |
| 8 | VERIFICATION_LOOP | Must run tests before claiming done |
| 9 | SURGICAL_CHANGES | No drive-by refactors |
| 10 | CROSS_TOOL_COMPAT | Symlinks to CLAUDE.md/GEMINI.md |

Output: `agents-audit-report-<timestamp>.md`

### `inject-caveman.sh` — Append caveman-mode directive

Appends the [caveman](https://github.com/JuliusBrussee/caveman) token-reduction directive to AGENTS.md files. Idempotent — skips files that already contain the marker.

```bash
./inject-caveman.sh /home/user/Dev
```

## Architecture

All scripts share a single index file. Consumer scripts refresh the index on every run:

```
discover-agents-md.sh   →  agents-md-index.log  ←  audit-agents-md.sh
                             (tab-separated)      ←  inject-caveman.sh
```

## Requirements

- Bash 4+
- coreutils (`find`, `grep`, `sed`, `wc`, `stat`)
- **Optional:** [Gemini CLI](https://github.com/google-gemini/gemini-cli) for LLM-powered audits (`npm install -g @google/gemini-cli`)

## License

MIT
