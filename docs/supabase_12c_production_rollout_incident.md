# Milestone 12C — production rollout incident and recovery evidence

Server revision `aish-supabase-003`. Target project `mfj***************tp`
(masked by `maskRef`, `tool/production_guard.ts`), region `ap-northeast-1`,
PostgreSQL 17.6.

This document records what actually happened when revision 003 reached the
production project: the migrations were applied **before** an approved
production preflight had ever run, why the preflight did not stop it, what was
done to contain it, and what the live database looks like now.

It is written as evidence, not as a runbook. The runbook is
`supabase_production_canary_rollout.md`; §15 of that document was corrected to
point here, because its previous claim that no remote command had been executed
is no longer true.

> **Scope of the incident.** A control failure, not a data-loss event. Eleven
> additive migrations applied cleanly, no rollback was attempted, no migration
> was repaired or re-stamped, no remote reset was run, and the production
> database holds zero business rows. The damage is to the assurance chain — the
> deployment was not gated — not to the data.

## 1. Incident

| Field | Value |
| --- | --- |
| Incident | Production migrations applied before an approved preflight |
| Detected | 2026-08-03, during rollout review |
| Severity | Control failure — process gate bypassed, no data impact |
| Data loss | None |
| Rollback | None attempted, none required |
| Recorded | 2026-08-03 10:42 UTC |

### 1.1 What was applied

All eleven migrations up to and including
`20260803000200_sync_change_journal_backfill_support.sql` are present in the
remote migration history and completed without error:

```text
20260802000100  domain_schema
20260802000200  server_metadata_and_ledger_guards
20260802000300  auth_helpers_and_rls
20260802000400  private_storage
20260802000500  sync_operation_infrastructure
20260802000600  document_numbering
20260802000700  transactional_sync_rpc
20260802000800  trusted_storage_upload
20260802000900  complete_transactional_workflows
20260803000100  deterministic_pull_change_feed
20260803000200  sync_change_journal_backfill_support
```

`app_meta.schema_revisions` holds the three matching revision rows:

```text
aish-supabase-001   2026-08-03 09:52:49.719383+00
aish-supabase-002   2026-08-03 09:53:16.893794+00
aish-supabase-003   2026-08-03 09:53:24.704538+00
```

### 1.2 Root cause

`tool/production_preflight.sh` was, at the time of the deployment, a **library**:
it defined `production_preflight()` and did nothing on its own. The operator
invoked it the way a check script is normally invoked:

```bash
bash tool/production_preflight.sh
```

Bash sourced the definitions, reached end of file and exited `0`. The function
was never called. No environment contract was validated, no confirmation token
was required, no backup identifier was demanded, no restore rehearsal was
asserted, no branch or working-tree check ran. An exit code of `0` was read as
"preflight passed", and the deployment proceeded.

The guard logic itself was not defective. Every refusal it implements was
present and unit-tested. The defect was that a file whose only safe use is
`source` could be executed directly and would report success by doing nothing —
a silent no-op in the one position where silence means "approved".

### 1.3 What did **not** happen

Stated explicitly so the record cannot be read as worse than it is:

| | |
| --- | --- |
| Spontaneous rollback | Not attempted |
| `supabase migration repair` | Not run — history was never falsified |
| `supabase db reset` against remote | Not run |
| Down migration | Not run |
| Journal backfill | **Not run** |
| Production canary | **Not run** |
| Realtime canary | **Not run** |
| Benchmark against production | **Not run** |
| Production used as covert staging | No |

## 2. Containment

| Step | Result |
| --- | --- |
| Remote operations halted | Done, immediately on detection |
| Local vs remote migration list compared | Identical, eleven entries |
| `supabase db push --dry-run` | Remote reports up to date — no pending migration |
| Remote `supabase db lint` | Clean |
| Post-migration logical backup | Taken — §3 |
| Backup checksums | Verified — §3 |
| Restore rehearsal, isolated local stack | PASS — §4 |
| Direct-execution guard | Fixed — `a98fd5d` |
| Regression coverage for the guard | Added — `c13d5d5` |

No migration was modified to fit this record, and no already-applied migration
file was touched.

## 3. Backup evidence

| Field | Value |
| --- | --- |
| Backup identifier | `20260803T095905Z-post-migration` |
| Type | Post-migration logical backup (roles + schema + data) |
| Location | Operator host, outside the repository |
| Files | `roles.sql`, `schema.sql`, `data.sql`, `SHA256SUMS` |
| Checksum status | **PASS** — all three files `OK` |
| Checksum re-verified | 2026-08-03 10:42 UTC, `sha256sum -c` |
| Approximate sizes | `schema.sql` ~293 KB, `data.sql` ~22 KB, `roles.sql` ~1 KB |

> **This is not a pre-deployment restore point.** The backup was taken *after*
> the migrations had already been applied. There is no logical backup of the
> production database in its pre-revision-003 state, and one cannot now be
> manufactured. Any future assertion that the deployment is reversible from this
> artifact would be false: restoring it reproduces the post-migration schema.

Two limits of a logical dump, recorded so they are not assumed away:

- **Supabase Storage binary objects are not included.** `storage.objects` rows
  are captured as metadata; the object bytes in the storage backend are not part
  of a logical database dump and are not covered by this backup.
- Roles are captured as the cluster emits them, including grants that are
  meaningful only on managed Supabase infrastructure — see §4.2.

## 4. Restore rehearsal

| Field | Value |
| --- | --- |
| Verified | **2026-08-03 10:34:53 UTC** |
| Target | Isolated local Supabase stack, project `aish_restore_rehearsal` |
| Production touched | No — rehearsal is a separate stack |
| Schema restore | **PASS** |
| Data restore | **PASS** |
| Object verification | **PASS** |
| Domain row count | 0 across every table checked |
| Privilege check | **PASS** |

### 4.1 Objects verified present after restore

```text
public.branches
public.sync_change_journal
public.sync_change_journal_backfill_marks
public.pull_sync_changes(bigint, integer, uuid, text[])
app_meta.schema_revisions   — 3 metadata rows
```

Privilege behaviour reproduced in the restored stack:

| Check | Result |
| --- | --- |
| `authenticated` may execute `public.pull_sync_changes` | PASS |
| `anon` may execute `public.pull_sync_changes` | Refused, as designed |
| `authenticated` may execute `app_private.pull_entity_visible` | Refused, as designed |
| Any backfill function executable by `authenticated` or `anon` | None |

Statement timeouts restored and verified:

```text
anon           3s
authenticated  8s
authenticator  8s
```

### 4.2 Role compatibility exception

`roles.sql` contains one statement that a local Supabase stack cannot apply,
because the grantee is a managed-platform role:

```sql
GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin";
```

For the rehearsal **only**, that single statement was removed into a derived
file, `roles.rehearsal.sql`. The original `roles.sql` in the backup set was not
modified, and its checksum in `SHA256SUMS` still verifies — see §3.

The exception is cosmetic for restore purposes: it grants a configuration
privilege to a Supabase-managed realtime role, and it does not participate in
application authorisation. `roles.sql` contains **no custom application roles**;
the application's authorisation model rests entirely on `anon`, `authenticated`,
RLS policies and function ownership, all of which restored correctly.

A real production restore would run against managed Supabase infrastructure
where `supabase_realtime_admin` exists, so the statement would apply normally.

## 5. Live production verification

Read-only verification against the live production project, executed through the
Supabase SQL surface. No raw SQL was run through a shell, nothing was written,
and no credential was printed.

| Field | Value |
| --- | --- |
| Verified | **2026-08-03 10:42 UTC** |
| Project | `mfj***************tp` |
| Status | `ACTIVE_HEALTHY` |
| Mode | Read-only `SELECT` / catalogue inspection only |
| Result | **PASS** |

### 5.1 Live row counts

| Relation | Live rows |
| --- | --- |
| `public.branches` | 0 |
| `public.users` | 0 |
| `public.items` | 0 |
| `public.item_batches` | 0 |
| `public.stock_locations` | 0 |
| `public.stock_balances` | 0 |
| `public.stock_movements` | 0 |
| `public.purchase_requests` | 0 |
| `public.delivery_orders` | 0 |
| `public.sync_change_journal` | 0 |
| `public.sync_entity_field_versions` | 0 |
| `public.sync_change_journal_backfill_marks` | 0 |
| `public.sync_change_journal_backfill_runs` | 0 |
| `auth.users` | 0 |
| `storage.objects` | 0 |

This is **live** evidence, taken from the production database itself. It is not
inferred from the dump and not inferred from the restore rehearsal.

### 5.2 Live privilege checks

Resolved signature:
`public.pull_sync_changes(after_cursor bigint, batch_limit integer, device_id uuid, entity_types text[])`

| Function | `authenticated` | `anon` | Expected | Verdict |
| --- | --- | --- | --- | --- |
| `public.pull_sync_changes(bigint,integer,uuid,text[])` | **true** | **false** | true / false | PASS |
| `app_private.pull_entity_visible(text,uuid)` | false | false | false | PASS |
| `app_private.pull_entity_payload` | false | false | false | PASS |
| `app_private.pull_commit_horizon` | false | false | false | PASS |
| `app_private.prune_sync_change_journal` | false | false | false | PASS |
| `app_private.backfill_sync_change_journal` | false | false | false | PASS |
| `app_private.backfill_entity_type_order` | false | false | false | PASS |
| `app_private.sync_backfill_coverage` | false | false | false | PASS |
| `public.admin_backfill_sync_change_journal` | false | false | false | PASS |
| `public.admin_sync_backfill_coverage` | false | false | false | PASS |

No private helper is reachable by a client role, `anon` cannot pull, and no
administrative backfill entry point is exposed to a session token.

### 5.3 Live journal posture and timeouts

| Relation | RLS enabled | RLS forced |
| --- | --- | --- |
| `public.sync_change_journal` | true | true |
| `public.sync_change_journal_backfill_marks` | true | true |
| `public.sync_change_journal_backfill_runs` | true | true |

`sync_change_journal` carries exactly one policy, `sync_change_journal_read_scope`,
command `r` (SELECT). No INSERT, UPDATE or DELETE policy exists — matching the
GO/NO-GO condition in the canary runbook.

Live role statement timeouts:

```text
anon           statement_timeout=3s
authenticated  statement_timeout=8s
authenticator  statement_timeout=8s
```

## 6. Backfill decision — SKIP

Every table the backfill would read, and every table it would write, is empty in
live production (§5.1):

```text
branches, users, items, item_batches, stock_locations, stock_balances,
stock_movements, purchase_requests, delivery_orders        all 0
sync_change_journal                                            0
sync_entity_field_versions                                     0
sync_change_journal_backfill_marks                             0
sync_change_journal_backfill_runs                              0
```

**Decision: SKIP.** Reasons:

1. There is no pre-existing entity anywhere in the database that needs a
   baseline journal row. Backfill exists to give rows that predate the journal a
   starting `server_version`; no such row exists.
2. Every row created from now on enters the journal through the normal triggers
   installed by `20260803000100_deterministic_pull_change_feed.sql`. New data
   does not need, and must not receive, a backfill baseline.
3. Running a backfill over zero rows performs no useful work.
4. Writing an empty run ledger purely so a status table shows "backfill
   executed" would be manufacturing evidence. The honest record is that the
   operation was unnecessary, which is what this section states.

This decision is bound to the row counts in §5.1 at 2026-08-03 10:42 UTC. **If
production is later seeded before the canary runs, this SKIP is void** and the
guarded path in `supabase_production_canary_rollout.md` §7 applies instead:
dry-run first, one entity type, batch size at most 25, `max_batches=1`, business
invariants captured either side of the batch, and a full stop on any change to a
business row, `updated_at` or `server_version`.

## 7. Guard fix

| Commit | Change |
| --- | --- |
| `a98fd5d` | `fix: harden production preflight invocation` |
| `c13d5d5` | `test: cover production preflight shell guard` |

Behaviour after the fix, re-verified 2026-08-03 10:42 UTC:

| Case | Result |
| --- | --- |
| `bash tool/production_preflight.sh` (direct execution) | **Refused, exit 64** |
| `source tool/production_preflight.sh` (library use) | Succeeds, defines `production_preflight` |
| Placeholder values in the environment contract | Refused |
| `deno test --allow-env tool/production_guard_test.ts` | **21 passed, 0 failed** |
| `bash tool/production_preflight_shell_test.sh` | **PASS** |
| `bash -n tool/*.sh` | PASS |
| `deno check tool/*.ts` | PASS |

Every production runner was audited to confirm it both sources the library and
actually calls the function — the failure mode that caused this incident cannot
recur silently through a wrapper:

| Runner | Sources library | Calls `production_preflight` |
| --- | --- | --- |
| `tool/run_supabase_production_preflight.sh` | yes | yes |
| `tool/run_verify_supabase_production_migrations.sh` | yes | yes |
| `tool/run_supabase_production_backfill_canary.sh` | yes | yes |
| `tool/run_supabase_production_canary_e2e.sh` | yes | yes |
| `tool/run_supabase_production_realtime_canary.sh` | yes | yes |
| `tool/run_benchmark_supabase_production_readonly.sh` | yes | yes |

None of them bypasses the placeholder check, the restore blocker, the branch
check or the dirty-tree check.

## 8. What remains blocked

The production credentials, change ticket, maintenance window and operator
acknowledgement required by the runbook are **not present** in this environment.
An operator file `.env.production.local` now exists (untracked, `chmod 600`), but
the fields that must carry real operational data are still unavailable — see
§8.1.

| Gate | Status |
| --- | --- |
| Live production verification | **PASS** — §5 |
| Live privilege verification | **PASS** — §5.2 |
| Backup evidence | **PASS** — §3 |
| Restore rehearsal | **PASS** — §4 |
| Backfill | **SKIPPED** — §6, justified by live zero rows |
| Approved production preflight run | **BLOCKED** — no credentials, no ticket, no window, no acknowledgement |
| Production canary | **BLOCKED** — depends on preflight |
| Realtime canary | **BLOCKED** — depends on canary |
| Low-load benchmark | **NOT RUN** — depends on canary |
| GO / NO-GO | **HOLD** |

`BLOCKED` here means the approved runner would refuse to start, which is the
correct behaviour. It must not be recorded as `PASS` on the strength of the
live read-only verification — that verification proves the schema and privilege
posture, not that the sync contract works end to end under a real session.

### 8.1 Environment contract audit — 2026-08-03

An operator environment file was prepared at `.env.production.local`. It is
untracked, `git check-ignore` confirms it is ignored, and its mode is `600`. Its
contents were never printed; every check below reports a status, never a value.

**The state it was found in.** The file was the 110-line
`.env.production.example` copied verbatim, with a second block appended. That
produced 13 duplicate keys, and the appended
`AISH_MAINTENANCE_WINDOW=<FORMAT_WINDOW_SESUAI_FILE_EXAMPLE>` made `bash -n`
fail at line 121. An unquoted `<` is a redirection, so sourcing the file aborted
part-way through — which is why the earlier run appeared to fail on
`AISH_BACKUP_IDENTIFIER` rather than on the syntax error that actually stopped
it. A partially-sourced environment is the failure mode this contract exists to
prevent: it leaves some variables set and others not, with no error at the point
of use.

**What the appended block contained.** Two fields were checked for provenance
without disclosing them. The appended `AISH_CHANGE_TICKET` differed from the
example and satisfied the guard's regex, but its shape was a self-descriptive
identifier assembled from the task itself, not an identifier issued by a change
management system. It was removed. A ticket that passes a regex but names no
real change record defeats the entire purpose of the gate — the guard can only
check the shape, so the honesty of the value is the operator's contribution, and
it cannot be manufactured here. The appended `AISH_OPERATOR_ACKNOWLEDGEMENT` was
a 5-character string of unverified origin; it too was removed rather than
recorded as an acknowledgement nobody gave.

**What the file was rebuilt to contain.** A single deduplicated block holding
only values that follow from the authorised rollout facts:

| Variable | Status | Source |
| --- | --- | --- |
| `AISH_TARGET_ENV` | SET | fixed — `production` |
| `APP_ENV` | SET | fixed — `production` |
| `AISH_PRODUCTION_CONFIRM` | SET | fixed token in `production_guard.ts` |
| `AISH_PRODUCTION_SECOND_CONFIRM` | SET | restates the project ref |
| `AISH_PRODUCTION_PROJECT_REF` | SET | authorised project ref |
| `AISH_PRODUCTION_ALLOWED_HOST` | SET | exact hostname, no scheme |
| `AISH_PRODUCTION_ALLOWED_BRANCH` | SET | `chore/12c-staging-rollout` |
| `AISH_BACKUP_IDENTIFIER` | SET | `20260803T133929Z-pre-canary`, §3 |
| `AISH_RESTORE_REHEARSAL_CONFIRMED` | SET | `true`, justified by §4 |
| `SUPABASE_URL` | SET | non-secret endpoint |
| `AISH_CHANGE_TICKET` | **MISSING** | requires a real change record |
| `AISH_MAINTENANCE_WINDOW` | **MISSING** | requires the real approved window |
| `AISH_OPERATOR_ACKNOWLEDGEMENT` | **MISSING** | requires a named operator |
| `SUPABASE_ANON_KEY` | **MISSING** | operator secret store |
| `SUPABASE_SERVICE_ROLE_KEY` | **MISSING** | operator secret store |

`AISH_PRODUCTION_ALLOWED_HOST` takes a bare hostname, not a URL: the guard
compares it against `new URL(SUPABASE_URL).hostname` and separately derives the
project ref from its first label, so a scheme, a wildcard or a list is refused.

The five MISSING variables are absent from the file rather than filled with a
plausible value. The guard would reject a placeholder anyway, but the reason for
leaving them out is not that the guard would catch them — it is that a canary
authorised by an invented ticket, inside an invented window, acknowledged by
nobody, produces evidence that cannot be audited afterwards.

**Validation after the rebuild.**

| Check | Result |
| --- | --- |
| `bash -n .env.production.local` | **PASS** — exit 0, no output |
| Placeholder scan (`replace-with`, `PLACEHOLDER`, `FORMAT_`, `TODO`, `CHANGEME`, `<`, `>`) | **PASS** — no matches |
| Duplicate key scan | **PASS** — no duplicates |
| Mode | **PASS** — `600` |
| `git check-ignore` | **PASS** — ignored |
| Tracked by git | **PASS** — not tracked |

The file was never sourced. With five required variables missing, sourcing it
and invoking the runner would only reproduce a refusal that is already known
with certainty, while loading a half-complete production contract into a live
shell.

**Preflight status: BLOCKED, not run.** The approved runner is
`bash tool/run_supabase_production_preflight.sh`. It was not invoked. The first
refusal it would emit is `production_env_missing: AISH_CHANGE_TICKET`, from
`production_require_var` in `tool/production_preflight.sh`, before any
credential is read. No refusal code is recorded below as observed output,
because none was observed.

**Backup re-validation, 2026-08-03.** Independently re-checked at the time of
this audit:

| Check | Result |
| --- | --- |
| `20260803T133929Z-pre-canary` directory exists | **PASS** |
| `roles.sql`, `schema.sql`, `data.sql`, `SHA256SUMS` present | **PASS** |
| `sha256sum -c SHA256SUMS` | **PASS** — 3/3 OK |
| No rehearsal artefacts mixed into the canonical set | **PASS** — 4 files, exactly the canonical set |

## 9. Corrective actions

| # | Action | Status |
| --- | --- | --- |
| 1 | Make direct execution of the preflight library fail loudly (`exit 64`) | Done — `a98fd5d` |
| 2 | Regression-test direct execution, sourcing and placeholder refusal | Done — `c13d5d5` |
| 3 | Audit every production runner for source-and-call | Done — §7 |
| 4 | Verify live production row counts and privileges | Done — §5 |
| 5 | Record backup and restore evidence honestly, including the missing pre-deployment restore point | Done — §3 |
| 6 | Correct §15 of the canary runbook, which claimed no remote command had run | Done |
| 7 | Run the approved preflight through `tool/run_supabase_production_preflight.sh` | **Pending operator** — blocked on §8.1 |
| 7a | Rebuild `.env.production.local` free of duplicates, placeholders and syntax errors | Done — §8.1 |
| 7b | Remove the synthesised change ticket and unverified acknowledgement | Done — §8.1 |
| 7c | Supply a real change ticket, maintenance window, operator acknowledgement and the two Supabase keys | **Pending operator** |
| 8 | Run the production canary inside a dedicated namespace | **Pending operator** |
| 9 | Obtain a pre-change backup before any future production operation | **Pending operator** |

## 10. Lessons

1. **A check that can exit 0 without checking anything is worse than no check.**
   The library was correct; its failure mode was silence. Any script whose only
   valid use is `source` must refuse direct execution.
2. **Exit code 0 is not evidence.** The preflight now emits an explicit verdict,
   and the evidence recorded in a rollout document must name the runner that
   produced it, not merely assert that a gate passed.
3. **Take the backup before the change, not after.** The post-migration backup
   is useful for restore rehearsal and for future recovery, but it can never
   serve as the pre-deployment restore point that the runbook assumed existed.
4. **An empty database is not a licence to skip verification.** The row counts
   are zero, but that is a *finding* from live production, not an assumption —
   and it is what justifies the backfill SKIP.

## 11. Canary namespace audit, 2026-08-03 — held before the first write

A second audit, run before the canary was allowed to write anything to
production, found a fail-safe gap in `tool/production_canary_namespace.ts`. The
canary was **not run**. Full detail is in
`supabase_production_canary_rollout.md` §17; the incident-relevant summary:

**Finding.** `ProductionCanaryNamespace.create()` performed all fifteen domain
inserts and four Auth `createUser` calls before returning the instance, so the
harnesses' `try`/`finally` could not reach `retire()` until setup had already
fully succeeded. A fault partway through left production rows active with
nothing tracking them. The worst case was an Auth identity created successfully
whose `public.users` or `user_auth_links` insert then failed: the actor was only
appended to `actors` after all three steps, so a live production credential
would have been invisible to cleanup.

Two further defects: retirement counted `entry.ids.length` as retired whenever
PostgREST returned no error — proof the statement was accepted, not that any row
matched — and `user_auth_links` was created but appeared in neither the
retirement list nor the left-in-place report.

**Why it did not become an incident.** The gap was found by reading the tooling,
not by running it. No production canary command has been executed. The live
production empty-state recheck at 2026-08-03T14:42:28Z is a read, and it
returned 0 for all fifteen relations, which is what keeps the backfill at SKIP.

**Corrective actions.**

| # | Action | Status |
| --- | --- | --- |
| 10 | Construct the namespace instance before the first remote write and run setup inside a cleanup-protected `try` | Done |
| 11 | Record each Auth identity immediately after `createUser`, before the inserts that depend on it | Done |
| 12 | Drive cleanup from created identities rather than fully configured actors | Done |
| 13 | Verify retirement against the ids the server actually updated; report `requested`/`matched`/`retired`/`missing` | Done |
| 14 | Give `user_auth_links` an explicit policy — left in place, never deleted, credential neutralised at the Auth identity | Done |
| 15 | Track the purchase-request child rows the push payload names | Done |
| 16 | Make `retire()` idempotent | Done |
| 17 | Add deterministic failure-injection and static-regression tests | Done — 36 tests |
| 18 | Re-run the approved production preflight from the new HEAD | **Pending operator** — the `14380dc` PASS is stale |
| 19 | Human review of the fail-safe change before any canary run | **Pending operator** |

**Lesson 5. A cleanup path that has never been made to run is not a cleanup
path.** The retirement logic was correct in isolation and unreachable in exactly
the situation it existed for. What proved it now is not review but deterministic
failure injection at every setup step — thirteen of them — asserted against the
calls a fake backend actually received.

**Lesson 6. "No error" is not "it happened".** A write path that reports success
from the absence of an error reports the one thing the server never told it. The
retirement update now returns its matched ids and the report says how many of the
requested rows actually changed.

**Lesson 7. Record a credential the moment it exists.** Ordering the bookkeeping
after the work is convenient and, for anything that creates a login, wrong. The
window between "the server has it" and "cleanup knows about it" is now one
statement wide.

---

## 12. Production E2E canary, 2026-08-03 — FAIL 32/33

The canary described in §11 was run against production. It failed. This section
is the record of that run, of two process deviations found afterwards, and of
the work done to contain and diagnose it. Nothing here was retried against
production, and nothing here changes the verdict.

| Field | Value |
| --- | --- |
| Branch / commit | `chore/12c-staging-rollout` / `8193560` |
| Project | `mfj*…**tp`, server revision `aish-supabase-003` |
| Change ticket | GH-2, PR #1 |
| Backup | `20260803T152802Z-pre-canary-8193560`, taken 2026-08-03T15:28:02Z |
| Backup manifest sha256 | `6d675c145016dbce8997f14fd0a52ebd88d28d2770dd86710d03ebe28c09b4ed` |
| Preflight | **PASS — 28/28**, 0 stop conditions, READ-ONLY, 2026-08-03T15:31:19.752Z |
| Canary namespace | `aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96` |
| Canary started | 2026-08-03T15:32:41.208Z |
| Canary finished | 2026-08-03T15:33:12.670Z |
| **Result** | **FAIL — 32/33** |
| Failed check | `realtime/a_scope_change_produces_an_invalidation` |
| Standalone Realtime canary | **NOT RUN** |
| Benchmark | **NOT RUN** |
| Backfill | **SKIPPED** |
| **GO/NO-GO** | **HOLD** |
| **Production retry** | **BLOCKED** |

### 12.1 Timeline

| UTC | Event |
| --- | --- |
| 15:28:02 | Pre-canary backup taken; `roles.sql`, `schema.sql`, `data.sql`, `SHA256SUMS` written, checksums verified |
| 15:31:19 | Production preflight — PASS 28/28, read-only, 0 stop conditions. Journal 0 rows, max cursor 0, 0 registered devices, `in_realtime_publication = true` |
| ~15:32:38 | Canary namespace minted |
| 15:32:41 | Canary run started |
| 15:33:12 | Canary run finished — FAIL 32/33 |
| 15:52 | Evidence preserved and checksummed; containment begins |
| 15:58–16:01 | Restore rehearsal of the pre-canary backup on an isolated scratch database — **post-canary**, see §12.5 |
| 16:04–16:10 | Realtime failure reproduced locally, root cause isolated — see §12.7 |

### 12.2 What passed

Thirty-two of thirty-three. The sync contract itself held under production:

* **12B push** accepted; an identical replay recognised as a replay; the server
  assigned the document number.
* **Deterministic 12C pull** — a drain from cursor 0 terminated inside budget,
  the cursor advanced monotonically, draining twice returned the same sequence,
  an odd page size repeated nothing and skipped nothing, a cursor at the head
  returned an empty page, and a cursor beyond the server was refused.
* **Isolation** — branch B never saw branch A's room, store or document; branch
  A never saw branch B's room; scope fingerprints differed between actors;
  another actor's device was refused; a client could not write the journal.
* **Realtime subscription** reached `SUBSCRIBED`.
* **Pull after the update supplied the current state.**
* **Disconnect and catch-up** from the durable cursor worked; the cursor
  advanced; the caught-up state was the server's current state.
* **Ledger** — duplicate movements 0, negative balances 0, the canary posted no
  stock movement and changed no stock balance. `covers_whole_ledger = true`.
* **Retirement** — 19 rows created, 19 requested, **19 retired**, 0 missing.
* **Auth identities** — 4 created, **4 disabled**, 0 failures. Banned, not
  deleted; that is the policy.

### 12.3 What failed

```
realtime/a_scope_change_produces_an_invalidation   FAIL
```

No Realtime invalidation frame reached the subscriber inside the harness's
20-second window, for a room the same actor could read and that the pull
returned correctly moments later.

The report recorded this as a bare `false` with an **empty detail string**. That
is itself a defect: the single boolean cannot distinguish a missing journal row
from an RLS drop from a late frame, and an operator holding the report had no
way to tell which had happened. §12.8 fixes it.

### 12.4 Process deviations — found AFTER the canary

These are recorded as found. Neither is restated as a gate that completed before
the production write, because neither did.

**Deviation 1 — the static safety suite never ran.** It was invoked as

```bash
deno test tool/production_canary_safety_test.ts
```

without `--allow-read`. Deno refused the suite access to the source files it
reads and it reported **0/11**. This was *not* an assertion failure. It was the
gate not executing at all, and the production write proceeding behind it.

**Deviation 2 — no restore rehearsal specific to this backup.**
`.env.production.local` declared `AISH_RESTORE_REHEARSAL_CONFIRMED=true` and the
canary report carries `restore_rehearsal_confirmed: true`, but at the time the
canary ran there was no evidence of a rehearsal against
`20260803T152802Z-pre-canary-8193560`. The backup itself was created correctly
and its checksums verify. An environment variable asserting a rehearsal is a
declaration, not evidence — the two were not the same thing here.

Both were found after the write, during containment.

### 12.5 Post-canary validation

Everything below happened **after** the failed canary. None of it may be read as
a gate that completed before the write.

| Item | Result | Timing |
| --- | --- | --- |
| Evidence preserved and checksummed | **PASS** | post-canary |
| `deno test --allow-read tool/production_canary_safety_test.ts` | **PASS — 11/11**, then 20/20 after hardening | post-canary |
| `bash -n tool/*.sh` | PASS | post-canary |
| `bash tool/production_preflight_shell_test.sh` | PASS | post-canary |
| `deno test --allow-env tool/production_guard_test.ts` | PASS — 21/21 | post-canary |
| `deno test tool/production_canary_namespace_test.ts` | PASS — 25/25 | post-canary |
| `deno check tool/*.ts` | PASS | post-canary |
| Restore rehearsal of `20260803T152802Z-pre-canary-8193560` | **PASS** | post-canary |

The safety suite's eleven assertions all pass once the permission is right. The
gate was sound; the invocation was not.

**Evidence, mode 700, alongside the backup it belongs to:**

```
$HOME/backups/aish_warehouse/20260803T152802Z-pre-canary-8193560/evidence/
  production-preflight-2026-08-03T15-31-19-752Z.json
  production-canary-e2e-2026-08-03T15-33-12-670Z.json
  ARTIFACT_SHA256SUMS          # sha256sum -c: OK, digests match the repo originals
  INCIDENT_METADATA.txt
  RESTORE_REHEARSAL_8193560.txt
```

The originals under `artifacts/production/` were copied with
`cp --preserve=mode,timestamps` and not modified.

**Restore rehearsal, 2026-08-03T15:58:29Z → 16:01:05Z.** Isolated scratch
database `aish_rehearsal_8193560` on the local Docker stack at `127.0.0.1:54322`
— not `mfjbqethoizpozgtqqtp.supabase.co`, no remote password, no linked-project
operation. Restored in order: roles, schema, data. Verified: 39 public tables,
11 public functions, 53 `app_private` functions, 34 policies, 69 user triggers;
`app_meta.schema_revisions` carrying `aish-supabase-003`; `pull_sync_changes`
executable by `authenticated` and refused to `anon`; `app_private.
pull_entity_visible` reachable by neither; journal RLS forced with the single
`sync_change_journal_read_scope` SELECT policy; `SELECT` granted to
`authenticated` and not to `anon`; statement timeouts 3s/8s/8s; every row count 0,
matching the preflight snapshot. Full record in `RESTORE_REHEARSAL_8193560.txt`.

Two compatibility exceptions, both on derived copies, the original dump
unchanged and still checksum-verifying: the managed-role grant
`GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin"` was
removed from a rehearsal copy of `roles.sql`, and the data restore ran with
`session_replication_role = 'replica'` for the circular `stock_movements` FK.

### 12.6 Read-only production verification — PENDING

Two operator files were prepared. Every statement in both is a `SELECT`, proven
by `tool/readonly_sql_check.ts`, and both were executed against the restored
production schema inside a `default_transaction_read_only` session to confirm
they parse and run without mutating:

```
artifacts/production/read-only-retirement-verification-8193560.sql
artifacts/production/read-only-realtime-audit-8193560.sql
```

They are run by pasting into the Supabase SQL Editor. Until an operator does
that and attaches the output:

* **REMOTE RETIREMENT VERIFICATION = PENDING**
* **READ-ONLY REALTIME AUDIT = PENDING**

Neither may be recorded as PASS on the strength of the canary's own report.

**Evidence gap found while writing them.** The canary report records retirement
*counts* — 19 created, 19 retired, 0 missing — but **not the exact row ids**.
Verification by exact id, the strongest form, is therefore impossible from the
artefact alone, and the queries fall back to the namespace token carried in each
row's name or reached through its canary branch. That is sound for a `SELECT`,
but weaker than an id list, and it is why corrective action 24 exists.

### 12.7 Realtime root cause

Facts, hypotheses and unknowns are kept apart deliberately.

#### Facts from the report

1. `realtime/subscription_established` **PASS** — the channel reached
   `SUBSCRIBED`.
2. `realtime/a_scope_change_produces_an_invalidation` **FAIL** — no frame naming
   the room inside 20 seconds.
3. `realtime/the_pull_triggered_by_the_frame_supplies_the_state` **PASS** — the
   drain after the mutation returned the room with the new name. The journal row
   therefore existed. (The check's name overstates it: the drain runs on the
   harness's own schedule, not on a frame. §12.8 makes the report say so.)
4. The preflight recorded `journal.in_realtime_publication = true` at 15:31:19Z,
   ninety seconds before the run.
5. The preflight recorded **0 journal rows, max cursor 0, 0 registered devices**.
   Production had never carried sync traffic.

#### Facts from the code

6. `pull_sync_changes` is `SECURITY DEFINER` and reads `sync_change_journal`
   directly. Since the post-mutation drain returned the row, the trigger wrote
   it, and it was committed before the 20-second wait even began — the trigger
   fires inside the `UPDATE`'s transaction, and the update had already returned.
   **The row was present for the whole window.**
7. Because the pull is `SECURITY DEFINER`, **no check in the canary exercises
   `sync_change_journal_read_scope`** — the policy Realtime evaluates per
   subscriber. The Realtime frame was the only thing that depended on it, and it
   was the only thing that failed.
8. `supabase/config.toml` had `[realtime] enabled = false`. The local stack had
   no `supabase_realtime` publication at all, so the Realtime path had **never
   been exercised outside a remote project**. Staging and production were the
   only places it had ever run.

#### Facts from the backup

9. The dump taken at 15:28:02Z contains, at `schema.sql:6158`:
   `ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."sync_change_journal";`
   Independent, offline, timestamped confirmation of fact 4. **Publication
   absence is refuted by two sources.**

#### Facts from local reproduction

Realtime was enabled locally and `tool/realtime_journal_local_repro.ts` was
written to walk the production sequence hop by hop. Ten bounded iterations, no
burst, no load:

| Run | Condition | Result |
| --- | --- | --- |
| 1 | 10 iterations, Realtime service freshly started | **iteration 1 failed**, 2–10 delivered |
| 2 | 3 iterations, service already warm | 3/3 delivered |
| 3 | 3 iterations, immediately after `docker restart` of Realtime | **iteration 1 failed**, 2–3 delivered |

10. Delivery latency when it works: **min 67 ms, median 310 ms, p95 338 ms,
    max 349 ms.** Two orders of magnitude inside the 20-second deadline.
11. In every failing iteration the journal row **was** created, and the
    subscribing actor **could** `SELECT` it under RLS — the probe the canary
    never had. Classified `journal_visible_via_select_but_no_frame`.
12. The failing iterations were given 20 s plus a 10 s grace window. **No frame
    ever arrived.** The change was lost, not delayed.
13. The failure tracks the Realtime service's cold start, not the data, not the
    actor, not the policy: same fixture, same actor, same mutation, failing only
    on the first subscription after the service starts.

#### Leading hypothesis

**The first `postgres_changes` subscriber after the Realtime service starts can
miss changes, because `SUBSCRIBED` is acknowledged before the tenant's CDC
pipeline is streaming.** A logical replication slot only ever delivers WAL
written after it exists, so a mutation landing in that window is not late — it
is never replicated at all. Production had never had a Realtime subscriber
(fact 5), so the canary was plausibly the first, and would have hit exactly this
window.

This is a hypothesis about production, supported by a reproduction elsewhere. It
is not yet a fact about production. Section 5 of the read-only Realtime audit is
written to settle it.

#### Refuted

* Publication membership — facts 4 and 9.
* RLS on the journal — fact 11: the actor could read the row.
* The journal trigger — facts 3, 6 and 11: the row existed.
* Latency, and therefore any fix that consists of raising the timeout — facts 10
  and 12. The frame never arrives; twenty more seconds would have changed
  nothing.

#### Still unknown

* Whether production's Realtime service was in fact cold at 15:32:5x. Only the
  read-only audit, or Supabase's own service logs, can say.
* Whether the managed Realtime service idles a tenant with no subscribers, and
  on what schedule.
* Whether the canary was genuinely the first-ever subscriber on that project.

### 12.8 Corrective actions

| # | Action | Status |
| --- | --- | --- |
| 20 | Preserve preflight and canary reports with checksums, mode 700, beside the backup | **Done** |
| 21 | Run the safety suite with the permission it needs — 11/11, then 20/20 | **Done — post-canary** |
| 22 | One approved local-gate runner, `tool/run_production_canary_local_gates.sh`, so the invocation cannot be retyped wrong | **Done** |
| 23 | Restore rehearsal against this specific backup, isolated scratch | **Done — post-canary** |
| 24 | Record the created row ids in the canary report so retirement is verifiable from the artefact alone | **Open** |
| 25 | Diagnose the Realtime failure into named outcomes rather than one boolean | **Done** |
| 26 | Reproduce Realtime locally; enable Realtime in `config.toml` so the path is testable off-production | **Done** |
| 27 | Read-only production retirement verification | **PENDING operator** |
| 28 | Read-only production Realtime audit | **PENDING operator** |
| 29 | Fresh preflight before any future production activity — `8193560`'s is stale once new commits land | **PENDING operator** |
| 30 | Human review and explicit approval before any production retry | **PENDING operator** |

**Harness changes.** `tool/realtime_diagnostics.ts` classifies a Realtime
observation into one of seven named outcomes, and `outcomeIsPass` says yes to
exactly one of them, `delivered`. The production canary now records the channel's
status transitions, the subscription and mutation timestamps, first-frame time
and delivery latency, the frame count and masked frame entity ids, a sanitised
channel error, whether the journal row was created, and whether the subscribing
actor could `SELECT` it — the probe whose absence made the original failure
unreadable. It also asserts the actor's session exists **before** the channel is
opened, because a channel opened first is evaluated by Realtime as `anon`, which
has no `SELECT` on the journal and would drop every frame while the transport
looked healthy.

**What was deliberately not changed.** The 20-second deadline stands — the
evidence says the frame never arrives, so a longer wait buys nothing. The check
is still a positive assertion: a late frame, a frame for another entity and a
silent healthy channel all remain failures. No retry was added, no assertion was
made optional, no check was removed, and no isolation assertion was touched. The
one added observation window is bounded at 10 seconds, opens only after the
verdict is already decided, and exists solely so a report can say "arrived at
24 s" instead of "never arrived".

A **cold-start warm-up before subscribing** would very likely make the canary
pass. It is deliberately **not** implemented: it would mask a real production
Realtime property behind harness behaviour, and that is an operator's decision
to take knowingly, not one to slip in during containment.

### 12.9 Status after this section

| Item | Status |
| --- | --- |
| Production preflight for `8193560` | **PASS at the time**, now **STALE** — new commits have landed |
| Production E2E canary | **FAIL — 32/33** |
| Standalone production Realtime canary | **NOT RUN** |
| Production benchmark | **NOT RUN** |
| Production backfill | **SKIPPED** |
| Remote retirement verification | **PENDING** |
| Read-only Realtime audit | **PENDING** |
| Local gates | **PASS** |
| Restore rehearsal | **PASS — post-canary** |
| **GO/NO-GO** | **HOLD** |
| **Production retry** | **BLOCKED** |
| PR #1 | **Must not merge** |

### 12.10 Lessons

**Lesson 8. A gate that cannot fail loudly will fail silently.** `deno test`
without `--allow-read` reported zero tests and exited zero. Nothing in the
pipeline treated "0 tests passed" as different from "all tests passed". The
invocation now lives in one runner with the narrowest permission each suite
needs, and a test asserts that the documented command still carries it.

**Lesson 9. A confirmation is not evidence.** `AISH_RESTORE_REHEARSAL_CONFIRMED=true`
is an operator asserting something. The gate accepted the assertion and never
asked for the artefact. A backup identifier and a checksum were demanded; proof
that *this* dump had been restored was not.

**Lesson 10. A code path only production exercises is a failure mode only
production can find.** Realtime was switched off locally, so the entire
subscribe-and-invalidate path had never run outside a managed project. The first
time it was exercised under production conditions, it failed — and the local
suite could not even be pointed at the question. Realtime is now on in
`config.toml` and the path has a local reproduction.

**Lesson 11. One boolean is not a diagnosis.** `false` with an empty detail
string collapsed six distinct failures into one and sent the investigation to
the database to work out which. The verdict is unchanged and just as strict; what
changed is that the report now says *why*.
