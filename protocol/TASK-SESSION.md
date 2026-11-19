# Task-session protocol (lean)

A **task session** is one fresh `claude -p` run that does exactly one board task and exits. The runner gives it [TASK-PROMPT.md](TASK-PROMPT.md) (or the project's own prompt). This page explains the rules behind that prompt, so a project can copy the short version into its `CLAUDE.md` ([CLAUDE-SNIPPET.md](CLAUDE-SNIPPET.md)).

## Why these rules

Every tool call re-sends the whole context. Cache reads are cheap per token (~0.1×) but there are a lot of them: a 46-call task at ~60k context per call reads ~3M tokens. So the two levers are **fewer calls** and **smaller context per call**. Output (incl. thinking) is ~5× input, so a short receipt and medium effort matter too. Numbers: [../learnings/TOKEN-LEARNINGS.md](../learnings/TOKEN-LEARNINGS.md).

## Rules

1. **One task per session.** Mark `[x]`, commit, stop. The next task starts at ~0 context.
2. **Lean start.** The runner passes only the tools tasks use (`Bash,Read,Edit,Write,Glob,Grep,Agent`), project settings only, no MCP servers, no auto-memory, no dynamic system-prompt sections, capped Bash output. Measured: ~42k → ~12k fixed context per call. Don't re-enable things per task unless a task needs them.
3. **Read the named files directly.** If the task names files and line hints, read those. Use the `scout` (haiku, read-only) only when files are unknown or more than ~3 are involved. Never grep the whole repo in the main context.
4. **Fewer, bigger turns.** Batch independent reads/searches in ONE message. Combine shell steps into one Bash call. Read whole functions once instead of many 10–20-line slices (each slice is a full-context turn).
5. **Edit with Edit/Write only.** sed/perl/heredoc edits mangle backslashes and quotes; one task spent 5+ turns repairing them.
6. **Tests through the `tester` subagent** (haiku, Bash only, ≤8-line report) so test logs never enter the main context. Use the project's single-file test command; know which command secretly runs the whole suite and ban it.
7. **Never background-and-wait.** A session that backgrounds a long job and waits wakes repeatedly; every wake re-writes the context to cache (~100k cache-write) and re-reads it. Measured: 7 wakes ≈ 5× the cost of a normal task. Long jobs (benchmarks, rescans, queue drains) belong to the supervisor, who runs them as one zero-token background command.
8. **One live check for data-shape work.** A green unit test on fictional data can miss the real shape. Print one read-only count from the live data ("matched N of M") before committing; counts only, never private values.
9. **Circuit breaker.** After 3 failed fix attempts: revert uncommitted task files, mark `[!]` with one line why, stop. The runner stops the whole run on `[!]`.
10. **Short receipt.** ≤5 lines. The runner records tokens; the supervisor reads the receipt.
11. **Free helper (optional).** `node <kit>/runner/ask-gemini.mjs "question" <files>` for Haiku-level questions on code only. Any non-zero exit = skip it. Verify its answer with one targeted read.

## Subagents

| Agent | Model | Tools | Use |
|---|---|---|---|
| `scout` | haiku | Read, Grep, Glob | file map when the task doesn't name files |
| `tester` | haiku | Bash | run named tests + type check, ≤8-line result |
| one `sonnet` coder (optional) | sonnet | default | well-bounded UI/wiring/tests when the main session is Opus; give exact paths and assertions, restate guardrails (subagents don't reliably see CLAUDE.md) |

Never run subagents in parallel in a task session (each starts cold and uncached). Templates: [agents/](agents/).
