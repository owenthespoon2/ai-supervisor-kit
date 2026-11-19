# CLAUDE.md snippet for an adopting project

Paste the block below into the project's `CLAUDE.md` and fill the `<...>` placeholders. Keep `CLAUDE.md` short: every session reads it on every call.

```markdown
## Lean routing (token budget first)

1. One `[ ]` task per session from `<BOARD.md>`: mark `[x]`, commit only task files + board, stop.
2. If the task names files, read them directly (whole functions, one call). Use the `scout` subagent only when files are unknown. Never grep the whole repo yourself.
3. Fewer, bigger turns: batch independent reads in one message, combine shell steps, never read the same file twice.
4. Edit only with Edit/Write (never sed/perl/heredoc).
5. Tests via the `tester` subagent. One test file: `<single-file test command>`. Types: `<check command> 2>&1 | tail -n 25`. Never `<command that runs the whole suite by surprise>`.
6. Never background-and-wait on long jobs (benchmarks, rescans): leave them to the supervisor and say so in the receipt.
7. After 3 failed attempts: revert task files, mark `[!]` with one line why, stop.

## Guardrails

- Read-only sources: never write to `<protected source folders>`.
- Private data: never put real names, amounts, emails or real file paths in code, tests, commits or the board. Fictional fixtures only. Reading local data to debug is fine; never copy it into git.
- Protected files (never modify or stage): `<TASKS.md, PROJECT.md, ...>`.
- Money: `<e.g. subscription only; never add API keys or enable paid usage>`.
```
