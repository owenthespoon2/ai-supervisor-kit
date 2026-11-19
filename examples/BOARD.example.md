# EXAMPLE APP — ACTIVE BOARD (MAX 60 LINES)

## RULES (details in CLAUDE.md)
- Fictional data only in code, tests, commits and this board (`Acme Mart`, `Sample Bank`, `Alex`).
- One test file: `pnpm --filter web exec vitest run <file> --reporter=dot`. Types: `pnpm --filter web check 2>&1 | tail -n 25`.

## ACTIVE QUEUE (one task per session)
- [x] **A1:** Add `GET /health/accuracy.json` returning counts only (`apps/web/src/routes/health/accuracy.json/+server.ts`, new `apps/web/src/lib/server/accuracy.ts` + test). Done when the endpoint returns `{items:{total,ok,failed}}`.
- [ ] **FIX-1:** [model:sonnet] Totals off by one on the summary card. Files: `apps/web/src/lib/server/summary.ts` (`buildSummary` ~L40–90: the loop skips the last row), `summary.test.ts`. Live symptom: `/health/accuracy.json` shows ok 9 of 10 for a fully valid fixture set. Done when the fictional 10-row test gives 10/10 and the live count matches the row count.
- [ ] **UI-2:** [model:sonnet] [effort:low] Move the "Last checked" line under the card title (`apps/web/src/lib/components/SummaryCard.svelte` ~L12–30). British English. Done when the page shows it under the title.
- [ ] **B3:** Background queue can stall on one job: add a per-job wall-clock timeout and recover stale jobs on start (`apps/web/src/lib/server/queue.ts`). Opus (concurrency). Fictional tests. Do NOT run the long rescan yourself: note in the receipt that the supervisor should run it.

## Known failures (not yours)
- none
