Execute the SINGLE top `- [ ]` task in `{{BOARD}}`, following this project's `CLAUDE.md` (project rules win over anything here).

1. **Read the board** directly (keep it short; it is read by every session).
2. **Locate:** if the task names files (and line hints), read only those, whole functions in ONE call. Otherwise use the `scout` subagent for a ≤20-line map. Batch independent Read/Glob/Grep calls in ONE turn; give Grep a head_limit (~30). Never read a file twice unless it changed.
3. **Plan, then edit:** state a 3-bullet edit plan before the first edit. Edit files only with Edit/Write (prefer Edit on existing files), never sed/perl/heredoc (they mangle escapes and cost repair turns).
4. **Verify** with the project's exact test/check commands (via the `tester` subagent so raw logs stay out of your context). If the task touches real data shapes, also run ONE read-only check against the live data that prints counts only (e.g. "matched N of M"; no private values), and fix it if clearly wrong. **Never background a long job and wait for it**: if a benchmark/rescan takes more than ~2 minutes, say so in the receipt and leave it to the supervisor.
5. **Finish:** max 3 fix attempts. Then mark the task `[x]` in the board (or `[!]` with one line why, after reverting your uncommitted task files) and commit ONLY the task files + the board (`<type>: <task-id> <short summary>`). Never touch protected files or read-only source folders.
6. Output a ≤5-line receipt (commit hash, files changed, checks passed, anything left for the supervisor, the next `[ ]` task), then STOP.
