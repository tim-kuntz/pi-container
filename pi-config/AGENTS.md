# Global Agent Rules (Container Variant)

## Runtime Context

- This session runs inside an Apple container. The host Mac is not directly accessible; file operations are limited exclusively to `/workspace`.

## Tool Discipline

- Before larger changes: `read` relevant files first, then `edit`
- `bash` for `ls`, `grep`, `find`, `rg` — not for logic
- `write` only for new files; modifications always via `edit`
- No `npm install`/`pip install` calls without explicit confirmation
- Do not write to any paths outside `/workspace`

## Sovereignty & Data Handling

- No calls to external APIs (curl, fetch, webhooks) without explicit instruction
- When scope is unclear: ask, don't guess

## Session Hygiene

- When approaching context limits: suggest a summary rather than endless compaction
- Errors are read and understood, not worked around
