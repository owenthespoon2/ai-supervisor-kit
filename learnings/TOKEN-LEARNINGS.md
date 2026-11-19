# Token learnings

Measured lessons from running this system, stated generally. **Read the rules of thumb first**; the evidence below backs them. Add new lessons to the running log at the bottom (format at the end). Projects may keep their own detailed notes; copy general lessons up here.

## Rules of thumb (current)

1. **Fewer calls beats everything.** Every call re-reads the whole context. Cache reads are ~60% of effective cost on a normal task.
2. **Shrink the fixed context per call first.** Lean flags took the fixed start from ~42k to ~12k tokens; per-call cache read dropped 35–50%.
3. **Name exact files + functions + line hints in the task.** 21–37 calls vs 74 without hints, on similar tasks.
4. **Sonnet for tasks that name exact files.** ~24k cache-read per call vs ~41k for Opus on comparable fixes; Opus for open-ended work.
5. **Never background-and-wait inside a task session.** 7 wakes ≈ 5× a normal task's cost. The supervisor runs long jobs as one zero-token background command.
6. **Supervisor wakes once per run**, verifies the batch together, and uses one-call checkpoint scripts. Fresh supervisor chat per night/batch.
7. **Pre-diagnose with one read-only count**, put the answer in the task. Cuts exploration turns and catches live-data mismatches that fictional unit tests miss.
8. **≤3 parts per task.** Bigger tasks cost the same as two smaller ones but risk an unfinished stop.
9. **Edit with Edit/Write, read whole functions.** Many 10–20-line `sed -n` reads and sed/heredoc edits produced the worst task measured (93 calls).
10. **Delegate test runs and file-finding to haiku subagents** (19–46k each) so logs never enter the main context.

## How to measure

The runner writes one JSON line per task to `<dataDir>/runs.jsonl`: `tokens` {input, output, cacheRead, cacheWrite}, `byModel[]`, `agents[]`, `toolCalls`, `minutes`, `effective`, `perCallCacheRead`.

Relative weights (API pricing ratios; subscription limits are *assumed* to track them, not verified):

| Kind | Weight vs fresh input |
|---|---|
| cache read | ~0.1× (one external report claims ~0.05× on newer models; unverified) |
| fresh input | 1× |
| cache write | ~1.25× (5-min TTL) / 2× (1-h TTL) |
| output (incl. thinking) | ~5× |

**Effective cost ≈ 0.1·cacheRead + input + 1.25·cacheWrite + 5·output.** Compare tasks by this, never by raw total (dominated by cheap cache reads).

Caveats: per-agent output in `agents[]` is a lower bound (stream events carry partial counts); `byModel[].output` is exact. Sample sizes are small (n = 1–6 per condition); treat single numbers as direction, not proof.

**1-turn probe** to measure fixed context: run `claude -p "Reply OK"` with the runner's flags and read the usage. Do this whenever flags, plugins, CLAUDE.md or the CLI version change.

## Evidence (first adopter, one night of runs, CLI 2.1.x)

### Per-task numbers

| Condition | Calls | Effective | Notes |
|---|---|---|---|
| Opus, default start, files named | 24–48 | 250k–640k | before any change |
| Opus, first task with "fewer, bigger turns" rule | 21 | ~300k | vs 37–48 for comparable tasks |
| Opus, many small reads + sed edits | 93 | ~1.0M | worst; 8.1M cache read |
| Opus, 4-part fix task | 44 | ~610k | ≈ two 2-part tasks, risk of unfinished stop |
| Opus, exact files + live symptom | 14–21 | 190k–290k | half the calls of the same kind of task without |
| **Opus, lean start** | 61 | — | **40.6k cache read per call** (was 55–87k) |
| **Sonnet, lean start, files named** | 41 | — | **23.9k per call** |
| Sonnet, files named, no line hints | 74 | ~300k | |
| **Sonnet, files + line hints** | 19–37 | **90k–180k** | 1.6–3.8 min each |
| Opus, measuring task that backgrounded a benchmark and waited | 67 | ~554k | 7 extra wakes, each ~100k cache write; 118 min |
| haiku `tester` / `scout` | — | 19k–46k | per use |

### Fixed context per call (1-turn probe)

| Setup | Fixed context |
|---|---|
| Default headless (29 tools, 5 plugins, MCP) | 41.8k |
| `--strict-mcp-config` + `--setting-sources project,local` + 7 tools | 13.3k |
| + auto-memory off + `--exclude-dynamic-system-prompt-sections` | 12.0k |

- Cross-session prompt cache works: a second session minutes later read 11.6k from cache and wrote only 1.8k. So splitting tasks finer costs little fixed overhead; the real per-session tax is the 5–7 baseline calls (read board, files, test, mark, commit).
- `--max-turns` exists but is hidden from `--help`; use it only as a runaway cap (e.g. 70).
- `--bare` broke subscription (OAuth) login in testing: don't use it.
- Flags an external report claimed that did **not** exist in the CLI tested: `--append-system-prompt-file`, `--thinking`. Always probe before adopting a flag.

### What worked

- Lean flags (above). Biggest single change.
- One-call checkpoint script; supervisor checks went from ~10 calls to ~3 per checkpoint.
- Supervisor running a ~1-hour benchmark as one background command: zero tokens while running, one wake. Doing a one-constant change itself instead of a task session saved ~90k.
- Writing fix tasks with ids + files + "print counts only" diagnosis: sessions skipped the scout.
- A haiku tester: test logs never entered the main context.
- Banning the test command that secretly ran the whole suite (~1,300 tests) on every check.
- A gate on the restart hook (skip while a task is mid-edit). Restarting during an edit was a real slip.

### What didn't (or not yet)

- "Fewer, bigger turns" as a rule alone: call counts stayed high until tasks also carried line hints.
- Skipping a slow acceptance check to save tokens: broke the task's acceptance; the supervisor had to run it anyway. Leave long checks to the supervisor explicitly instead.
- Fictional unit tests alone for data-shape work: passed, then failed on the live data → the one-live-count rule.
- Free Gemini Flash / stronger tiers: frequently 503-busy; Flash-Lite answered reliably. Generic research answers from a small model mostly confirmed what we had; deep-research reports were useful but contained wrong flag claims (verify by probe).
- Shell gotcha: Markdown backticks inside a bash double-quoted `node -e "..."` run as commands. Write the script to a file and run it.

### Open experiments

- `effort:low` vs `medium` on UI-only tasks (watch retry/`[!]` rate).
- Built-in concise output style (output is ~5×; measure output tokens per task).
- Whether `--setting-sources project,local` already drops all user plugins without losing auth (probe).
- Measure free-helper savings: calls and cache reads on tasks that used it vs not.
- Target: under 30 calls for a normal task.

## Running log

Newest at the bottom. One entry per measured finding or change.

```markdown
### YYYY-MM-DD — <short title> (<project or "general">)
- Measured: <condition> → <calls / effective / per-call> (n = <samples>)
- Change: <what was changed, where>
- Expected / result: <...>
- Status: applied | trial | rejected
```

### 2026-11-19 — kit created (general)
- Change: lessons above extracted from the first adopter's notes into this kit; runner records `effective` and `perCallCacheRead` per task directly.
- Status: applied
