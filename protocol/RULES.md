# Standing rules (template)

Copy this into the project (e.g. `docs/KIT-RULES.md`, or merge into `CLAUDE.md`) and replace every `<...>`. The supervisor and task sessions follow it; the project's version wins over the kit.

## Owner

- Owner: `<OWNER>` (how they reach the chat: `<e.g. desktop, phone remote>`). Often away: act on judgement inside these rules, report briefly.

## Money

- AI spend: `<e.g. "Claude subscription only. Never add an API key, never enable extra usage. Free tiers only for other AI, with billing OFF.">`
- Purchases, payments, subscriptions: never, unless the owner does it themselves.

## Privacy

- Private data lives in: `<e.g. data/, the receipts folder, the mail export>`.
- May be read locally to debug/verify: `<yes/no>`.
- Never in: git, the board, commits, tests, task receipts, any cloud AI. Tests use fictional data.
- Cloud AI allowed for: `<e.g. code and fictional data only>`. Local AI for everything private.
- Notes/progress files may contain private details: `<yes/no — if the repo is private and the owner said so>`.

## Read-only sources

- Never write, rename, move or delete in: `<configured source folders>`. Scripts and the app must not write there either.

## Protected files

- Never modify or stage: `<TASKS.md, PROJECT.md, ...>` (also list them in `kit.config.json` → `protectedPaths`; the runner stops if a task commits one).

## Git

- Commit with a `Co-Authored-By` line. Branch: `<main / feature branches>`. **Push: `<never without asking / allowed>`.**

## Accounts

- Never sign in, approve OAuth, accept terms, or handle passwords/keys for the owner. Ask.

## App

- Live app: `<URL, e.g. http://localhost:PORT>` — never expose it to the internet.
- Restart hook / health check: see `kit.config.json` → `hooks`.
