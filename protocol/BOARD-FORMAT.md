# Board format

The board (default `BOARD.md`, set by `board` in `kit.config.json`) is the queue the runner reads. Every task session reads it, so **keep it under ~60 lines**: move finished tasks out regularly (to a completed-tasks file) and keep long specs in separate docs that tasks link to.

## Task line

```
- [ ] **ID:** [model:sonnet] [effort:low] One-paragraph task. Files: `path/a.ts` (`fnName` ~L120–180), `path/a.test.ts`. Symptom/goal: ... Done when: ...
```

- Status: `[ ]` open, `[x]` done, `[!]` blocked (the runner stops the run).
- `**ID:**` letters, digits, `-`, `_`. The runner takes the **first** `- [ ]` line in the file, so order = priority.
- Tags (optional, anywhere on the line):
  - `[model:opus|sonnet|haiku]`: default `claude.defaultModel` (opus).
  - `[effort:low|medium|high|xhigh|max]`: default `claude.defaultEffort` (medium).
- One line per task. Line breaks inside a task make it invisible to the runner.

## Writing a good task (cheapest first)

1. **Exact files, functions and line hints.** Measured: same-sized tasks with line hints took 21–37 calls; with files but no hints, 74.
2. **The live symptom and how to check it** ("the endpoint shows X; done when it shows Y").
3. **Pre-diagnosis** from the supervisor: one read-only count script run before writing the task, answer pasted in.
4. **≤3 parts.** A 4-part fix cost the same as two 2-part ones but risked stopping unfinished.
5. **Acceptance in one sentence** ("Done when ...").
6. **No private data**: ids and counts, never names/amounts/emails/real paths.

## Suggested sections

```markdown
# <PROJECT> — ACTIVE BOARD (MAX 60 LINES)

## RULES (short; link to CLAUDE.md for the rest)
- ...

## ACTIVE QUEUE (one task per session)
- [ ] **A1:** ...

## Known failures (not yours)
- ...
```
