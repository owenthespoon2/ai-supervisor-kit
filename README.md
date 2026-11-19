# AI supervisor kit

A project-independent kit for running coding work with Claude Code **cheaply and unattended**:

- one **supervisor** chat that plans, verifies and wakes rarely,
- a **runner** that takes the top task from a Markdown board and runs one fresh headless `claude -p` session per task with lean flags, logging tokens per task,
- **zero-token watchers** that wake the supervisor only when a run ends or something breaks,
- **protocols** and **measured learnings** that keep both roles lean,
- a **research step** that has another (free) AI check for newer token-saving techniques before each new supervisor chat.

Built for: a subscription plan (no pay-per-token API), free tiers only for other AIs, private data that never leaves the PC. Windows (PowerShell + Git Bash) first; the bash scripts also run on macOS/Linux.

## What's in it

```
README.md                  this file + the starter prompts
kit.config.example.json    every setting, with notes (defaults for all scripts)
protocol/
  SUPERVISOR.md            supervisor role, loop, checkpoint routine, problem table
  TASK-SESSION.md          lean task-session rules and why
  TASK-PROMPT.md           the prompt the runner gives each task session ({{BOARD}} is filled in)
  BOARD-FORMAT.md          task line format, tags [model:...] [effort:...], how to write cheap tasks
  MODEL-ROUTING.md         Opus vs Sonnet vs haiku; free helpers; what data may go where
  RULES.md                 privacy / money / protected files template (placeholders)
  CLAUDE-SNIPPET.md        short block to paste into a project's CLAUDE.md
  agents/scout.md, tester.md   haiku subagent templates
runner/
  run-board.ps1            the runner (-DryRun shows the next task and command, runs nothing)
  watch.sh                 zero-token watcher: one line on RUN_FINISHED / TASK_PROBLEM / TOKEN_ALERT / STALLED / RUNNER_GONE
  checkpoint.sh            whole checkpoint in one call (last task cost, git, queue, gated restart, --check)
  wait-until.sh            zero-token wait for a supervisor's long job (queue / pid / file)
  restart-if-clean.sh      project restart hook, skipped while a task is mid-edit
  ask-gemini.mjs, gemini.mjs   free Gemini helper (code only; refuses private paths)
  kit-config.mjs           reads kit.config.json for the bash/node scripts
learnings/TOKEN-LEARNINGS.md   rules of thumb, cost formula, measured numbers, running log
research/                  pre-chat research prompt + script; dated notes YYYY-MM-DD.md
examples/                  example config and board for a web-app project
```

## Adopt it in a project (once, ~15 minutes)

1. Keep this kit in one place (e.g. `C:\Projects\ai-supervisor-kit`); projects point at it. Don't copy the scripts into projects.
2. In the project root:
   - copy `kit.config.example.json` → `kit.config.json`; set `board`, `dataDir` (gitignored), `protectedPaths`, `hooks` (restart / check / queue commands, or leave empty);
   - add `dataDir` to `.gitignore`;
   - create the board ([protocol/BOARD-FORMAT.md](protocol/BOARD-FORMAT.md); see [examples/BOARD.example.md](examples/BOARD.example.md));
   - paste [protocol/CLAUDE-SNIPPET.md](protocol/CLAUDE-SNIPPET.md) into `CLAUDE.md` and fill it in; fill in [protocol/RULES.md](protocol/RULES.md) (project copy);
   - copy `protocol/agents/*.md` to `.claude/agents/` and fill in the test commands and private folders.
3. Check: `powershell -NoProfile -File <kit>\runner\run-board.ps1 -Project <project> -DryRun`.
4. Optional: put a project-specific task prompt in the project and set `taskPrompt`; otherwise the kit's [protocol/TASK-PROMPT.md](protocol/TASK-PROMPT.md) is used.

A project that already has its own runner can adopt only the protocols and learnings first, and switch scripts later.

## Before each new supervisor chat: research (weekly is enough)

```bash
node <kit>/research/run-research.mjs
```

Writes `research/YYYY-MM-DD.md` (free Gemini, billing off), or use `--bundle` and a web AI. See [research/README.md](research/README.md).

## Starter prompts

Paste **one** of these into a new chat opened in the project folder. Replace `<KIT>` with the kit's path (or its repository link) — nothing else needs editing.

### Supervisor

```text
You are the SUPERVISOR for this project, using the AI supervisor kit at <KIT>.
Read in this order, narrowly: <KIT>/protocol/SUPERVISOR.md, the "Rules of thumb" section of <KIT>/learnings/TOKEN-LEARNINGS.md, the newest <KIT>/research/YYYY-MM-DD.md, then this project's kit.config.json, CLAUDE.md and board.
The project's own rules win over the kit. Never spend money on AI, never push without asking, private data never leaves this PC.
Then do the "Starting a supervisor chat" steps (auth check, runner state, -DryRun) and report in at most 5 lines. Wait for my go before the first launch.
```

### Task (manual, when not using the runner)

The runner already sends [protocol/TASK-PROMPT.md](protocol/TASK-PROMPT.md) to every task session. To do one task by hand in a fresh chat:

```text
Do the single top "- [ ]" task in the board, following this project's CLAUDE.md and <KIT>/protocol/TASK-PROMPT.md. One task only; commit, receipt, stop.
```

## Rules that never change

- **Money:** subscription only. Never an API key in this repo or any project, never paid usage, free tiers with billing off.
- **Privacy:** private data is read only locally and goes only to a local model. Never into git, boards, tests, receipts or a cloud AI. The research step sends only this kit's generic files.
- **Push:** never without the owner's say-so.
- **Measure, then adopt:** a research claim becomes a protocol rule only after a local probe or a measured task, logged in the learnings.
