# Model routing

Pick the cheapest model that will get the task right first time. A failed task costs a whole extra session.

## Claude (subscription only)

| Use | Model | Effort | Why |
|---|---|---|---|
| Task names exact files + line hints; UI, wiring, tests, one bounded fix | **sonnet** | medium (low for UI-only) | Measured ~24k cache-read per call vs ~41k for Opus on comparable tasks, and Sonnet is assumed to count less per token. 90–180k effective per task. |
| Open-ended, measuring, cross-module, migrations, concurrency, security/privacy boundaries, money logic, a retry after a failed attempt | **opus** | medium | Fewer wrong turns. |
| Locate files, run tests, summarise logs | **haiku** subagent (`scout`, `tester`) | — | 19–46k per use; keeps logs out of the main context. |
| Supervisor chat | strongest available | — | Judgement; it should wake rarely, so its per-wake cost matters more than its per-token price. |

Tag the board line: `[model:sonnet]`, `[effort:low]`. No tag = config default.

## Free helpers (no money, ever)

| Route | Roughly | Allowed data | How |
|---|---|---|---|
| Free Gemini API (AI Studio key, **billing OFF**) | Flash-Lite ≈ ≤Haiku (most quota, most reliable); Flash ≈ Haiku–Sonnet (often busy) | code and fictional data only (the free tier may be used to improve Google's products) | `runner/ask-gemini.mjs` |
| Web-app AI used by the owner (e.g. a free deep-research mode) | ≈ Sonnet | code, docs, fictional data | a prompt file + one attachment the owner pastes; one result file back |
| Local model (LM Studio, Ollama, ...) | < Haiku | **all private data** | the project's own integration |

Rules:
- Private data only ever goes to a local model.
- Any non-zero exit from a free helper = do the job yourself. Never retry in a loop; a 429 means the free quota is gone for the day.
- Verify helper answers with one targeted read before relying on them.
- Capability tiers change monthly; the research step ([../research/](../research/)) re-checks them.
