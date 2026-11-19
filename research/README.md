# Pre-chat research step

Token-saving techniques for Claude Code change every few weeks (new flags, caching rules, models, plan limits). Before starting a new supervisor chat — at least weekly — get another AI to research what's new and compare it with `protocol/` and `learnings/`. The result is a short dated note, `research/YYYY-MM-DD.md`, which the starter prompt tells the supervisor to read.

This costs no Claude tokens and no money.

## Route A — free Gemini API (one command)

Needs a Google AI Studio key in the `GEMINI_API_KEY` environment variable, on a project with **billing OFF** (then it can never charge). The key is never stored in this repo.

```bash
node research/run-research.mjs
```

It sends only this kit's generic files (no project files), asks for Google Search grounding (falls back without it if the free tier refuses; the note's footer says which), and writes `research/<today>.md`. Flash is tried first, then Flash-Lite.

## Route B — any web AI with search (best quality)

```bash
node research/run-research.mjs --bundle
```

Paste `research/.bundle.md` (gitignored) into a web AI with a free deep-research or search mode. Save its answer as `research/YYYY-MM-DD.md`.

## After the note exists

The supervisor (or the owner) reads "New ideas to try", picks **at most one or two**, verifies each with a local 1-turn probe (`claude -p "Reply OK"` with the runner flags), and records the result in `learnings/TOKEN-LEARNINGS.md` → Running log (applied / trial / rejected). Research notes are claims; learnings are measurements. Commit the note.
