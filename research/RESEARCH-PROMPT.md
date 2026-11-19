You are researching **current techniques for cutting token use in Claude Code and similar agent loops**, for a small one-person setup that runs on a flat **subscription plan** (no pay-per-token API, no paid tools; free tiers only).

## The setup (summary; full text is attached)

- A **supervisor** chat (Claude Code) launches a PowerShell runner that takes the top open task from a Markdown board and runs one fresh headless `claude -p` session per task, with lean flags (7 tools, project settings only, no MCP, no auto-memory, excluded dynamic system-prompt sections, `--max-turns`, capped Bash output), stream-json logging, and per-task token records.
- Task sessions follow a lean protocol: one task per session, read named files directly, batch calls, edit with Edit/Write, tests via a haiku subagent, never background-and-wait, short receipt.
- Routing: Sonnet for tasks naming exact files with line hints, Opus for open-ended work, haiku subagents for file-finding and tests, a free Gemini Flash-Lite helper for code-only questions.
- The supervisor waits on zero-token shell watchers and wakes once per run.
- Cost model: effective ≈ 0.1·cacheRead + input + 1.25·cacheWrite + 5·output.

Attached: the protocol files, the measured learnings, and the previous research note (if any).

## What to do

1. Search for what is **new or changed in the last ~3 months** (prefer official Anthropic docs and changelogs, the Claude Code release notes, and well-sourced engineering posts; say when a source is a forum or opinion): CLI flags and settings, prompt-caching behaviour and TTLs, subagent/agent features, output styles, context compaction/editing, hooks, model releases and how subscription limits count different models, headless/automation features, and community techniques for agent loops.
2. Compare each finding with the attached protocol and learnings.
3. Be concrete and checkable: exact flag/setting names, the version they appeared in, and a one-line way to verify on a local machine (e.g. a 1-turn probe). **Say plainly when you are not sure** a flag exists; earlier reports invented flags.
4. Ignore anything that costs money, needs an API key on a paid plan, or sends private data to a cloud service.

## Output (Markdown, at most ~80 lines, exactly these sections)

```markdown
# Token research — YYYY-MM-DD

## New ideas to try
- **<idea>** — what it is, expected saving, source (link), how to verify locally, risk. (most promising first, at most 8)

## Already doing (confirmed still current)
- <protocol item> — still recommended / changed because <...>

## Possibly outdated in our protocol
- <item> — why, source

## Model / plan changes
- <new models, how they count against subscription limits, free-tier changes for other AIs>

## Sources
- <title> — <url> — <date> — <official | blog | forum>
```
