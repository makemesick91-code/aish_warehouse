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
