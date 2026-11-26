# RC1 static validation record

Recorded: 26 November 2026. Scope: local package and the supplied backup ZIPs only.

## Passed locally

- Main inline JavaScript in `index.html`: Node.js `--check` passed after RC1 changes.
- `supabase-adapter.js`: Node.js `--check` passed.
- `supabase/functions/admin-users/index.ts`: TypeScript `transpileModule` reported zero syntax diagnostics; the emitted module also passed Node.js syntax check.
- Backup consistency re-check: 446 `app_docs` rows, 6 `app_users` rows, 0 duplicate `(collection,id)` keys, 0 invalid JSON documents, and no broken student/class/batch or attendance/grade student references.
- Legacy ownership mapping simulation: all 219 attendance and all 60 grade documents match exactly one `app_users` profile using `byPhone` as either email or phone. No ambiguous/unmatched ownership in this backup snapshot.
- RC1 UI assertions: Asia/Jakarta date calculation; past attendance date capped for accounts without `edit`; save handler also rejects past-date edit without `edit`; attendance/grade/presence/audit writes include `byId`; student deletion calls the transactional RPC.

## Not verified locally

- PostgreSQL execution/syntax of the two SQL migrations against the actual Supabase Preview schema.
- Actual Supabase Auth/RLS/Reatime behavior.
- Edge Function deployment/invocation.
- Cloudflare Pages Preview deployment and browser tests.

These need the live Preview project and must pass the Preview checklist before Production is considered.
