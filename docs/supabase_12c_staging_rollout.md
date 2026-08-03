# Milestone 12C — staging rollout runbook

Server revision `aish-supabase-003`. This document covers deploying revision 003
to a **staging** project, seeding the change journal with a baseline, verifying
it, and deciding whether the client release may proceed.

It does not cover production. Every script referenced here refuses to run
against a host that is not on the operator's staging allowlist, and none of them
has a destructive mode.

> **Production is a separate path.** If no staging project is available, do
> **not** point these tools at production and do **not** relax the allowlist to
> make them start. Production has its own guard, its own environment contract,
> its own confirmations and its own runbook:
> `supabase_production_canary_rollout.md`. Nothing in this document was changed
> to accommodate it, and no production tool reads a `AISH_STAGING_*` variable —
> the two contracts refuse to coexist in one shell, and
> `tool/production_guard_test.ts` asserts that neither confirmation token is
> accepted by the other environment.

Design lives in `supabase_12c_sync_design.md`, the contract in
`supabase_rpc_contracts.md`, the security posture in `supabase_security_model.md`
and the deployment inventory in `supabase_12c_remote_handoff.md`.

## 1. What the rollout adds

One additive migration, `20260803000200_sync_change_journal_backfill_support.sql`:

```text
table     public.sync_change_journal_backfill_runs
table     public.sync_change_journal_backfill_marks
function  app_private.backfill_entity_type_order()
function  app_private.backfill_sync_change_journal(uuid, text, text[], integer, integer, text, uuid, boolean)
function  app_private.sync_backfill_coverage(text)
function  app_private.sync_journal_retention_plan(integer)
function  app_private.sync_rollout_verification()
function  public.admin_backfill_sync_change_journal(...)     -- service_role only
function  public.admin_sync_backfill_coverage(text)          -- service_role only
function  public.admin_sync_journal_retention_plan(integer)  -- service_role only
function  public.admin_sync_rollout_verification()           -- service_role only
```

Nothing in `20260803000100` is altered and no public RPC signature changes.
`app_meta.schema_revisions` is deliberately **not** advanced: the client contract
is still `aish-supabase-003`, and bumping it would fail every 12C client's health
check over a migration with no client-visible surface. Whether the rollout
migration is applied is answered by `supabase_migrations.schema_migrations`,
which `tool/verify_supabase_12c_staging.ts` asserts on.

## 2. Configuration

Operator variables live in the environment, never in the repository. The tracked
contract is `.env.staging.example`; it carries names and placeholders only.

```bash
set -a; . /path/outside/the/repo/staging.env; set +a
```

The Flutter side uses `config/supabase.staging.example.json`, copied to
`config/supabase.staging.json` (gitignored). Only the publishable/anon key
belongs in a client build.

### Fail-closed rules every staging script applies

| Rule | Refusal |
| --- | --- |
| `AISH_STAGING_CONFIRM` must equal `I_UNDERSTAND_THIS_IS_STAGING` | `staging_confirmation_missing` |
| `AISH_TARGET_ENV` must be `staging` | `staging_target_env_invalid` |
| URL must be HTTPS | `staging_url_not_https` |
| Host or project ref containing `prod`, `production`, `live`, `prd` | `staging_refused_production_host` / `_ref` |
| Host must appear in `AISH_STAGING_HOST_ALLOWLIST` | `staging_host_not_allowlisted` |
| Project ref must appear in `AISH_STAGING_PROJECT_REF_ALLOWLIST` | `staging_project_ref_not_allowlisted` |
| `STAGING_ALLOW_DESTRUCTIVE_OPERATIONS` must be `false` | `staging_destructive_operations_refused` |
| Writing tools must run from `chore/12c-staging-rollout` | `staging_branch_refused` |
| Writing tools must run from a clean tree | `staging_working_tree_dirty` |
| Any argument resembling `db reset`, `drop`, `truncate` | `staging_destructive_command_refused` |

The allowlists are the load-bearing check. A variable named `SUPABASE_URL`
pointing at a host whose name contains "staging" proves nothing — an operator can
paste a production URL into it in one keystroke. The name check is a courtesy;
the allowlist is the control.

No script prints a key. `staging_guard.ts` registers every secret it reads and
scrubs it from every line — including interpolated error bodies — before it
reaches stdout.

## 3. Preflight record

Capture this **before** anything is deployed, and attach it to the rollout
ticket. `tool/verify_supabase_12c_staging.ts` produces most of it as JSON.

| Field | Where from |
| --- | --- |
| Project identity (masked ref, host) | script banner |
| Current server revision | `admin_sync_rollout_verification().server_revision` |
| Last applied migration | `.migrations` |
| Registered devices | `.devices.total` |
| Row count per syncable table | `admin_sync_backfill_coverage().entities[].rows` |
| Journal rows | `.journal.rows` |
| Max cursor | `.journal.max_change_seq` |
| Commit horizon | `.journal.commit_horizon` |
| Realtime publication state | `.journal.in_realtime_publication` |
| RLS and grants | `.journal.*`, `.privileges.*` |
| Backup identifier and checksum | §4 |
| Timestamp (UTC), operator | recorded by hand |
| App commit and tag | `git rev-parse HEAD`, `git tag --points-at HEAD` |

## 4. Backup

Take a backup and **prove it is restorable** before deploying. An unverified
backup is not a rollback plan; it is a hope.

Templates below use `$STAGING_DB_URL`, supplied by the operator environment and
never written down. Nothing in this repository stores a connection string.

```bash
# Full logical dump, custom format so it can be restored selectively.
pg_dump --format=custom --no-owner --no-privileges \
  --file="staging-$(date -u +%Y%m%dT%H%M%SZ).dump" "$STAGING_DB_URL"

# Schema only — the fast path for comparing objects after a migration.
pg_dump --format=plain --schema-only --no-owner --no-privileges \
  --file="staging-schema-$(date -u +%Y%m%dT%H%M%SZ).sql" "$STAGING_DB_URL"

# Data only.
pg_dump --format=custom --data-only --no-owner \
  --file="staging-data-$(date -u +%Y%m%dT%H%M%SZ).dump" "$STAGING_DB_URL"

# The sync tables specifically, so a journal problem can be investigated
# without restoring everything.
pg_dump --format=custom --no-owner \
  --table=public.sync_change_journal \
  --table=public.sync_entity_field_versions \
  --table=public.sync_devices \
  --table=public.sync_operations \
  --table=public.sync_conflicts \
  --file="staging-sync-$(date -u +%Y%m%dT%H%M%SZ).dump" "$STAGING_DB_URL"
```

Verification — a dump that cannot be listed cannot be restored:

```bash
pg_restore --list staging-*.dump > /dev/null && echo "dump readable"
sha256sum staging-*.dump | tee staging-backup-checksums.txt
```

Restore rehearsal, into a **scratch** database that is not staging and not
production:

```bash
createdb aish_restore_probe
pg_restore --no-owner --dbname=aish_restore_probe staging-*.dump
psql -d aish_restore_probe -c \
  "select count(*) from public.sync_change_journal"
dropdb aish_restore_probe
```

Storage metadata (Supabase Storage objects for `import-audit` and
`report-artifacts`) is exported through the Supabase dashboard or the management
API; record the bucket listing and object count alongside the dump.

Retention: keep staging backups encrypted at rest for 14 days, then destroy.
They contain synthetic data but also real project structure.

## 5. Runbook

Run in this order. Each step's gate must pass before the next begins.

```text
 1. preflight ............ tool/run_supabase_12c_verify_staging.sh   (pre-deploy snapshot)
 2. backup ............... §4, including the restore rehearsal
 3. deploy ............... npx supabase db push --linked
 4. verify privilege ..... tool/run_supabase_12c_verify_staging.sh
 5. dry-run backfill ..... tool/run_supabase_12c_backfill_staging.sh --dry-run
 6. execute backfill ..... tool/run_supabase_12c_backfill_staging.sh --execute
 7. verify backfill ...... tool/run_supabase_12c_verify_staging.sh
 8. check Realtime ....... verification asserts publication membership
 9. run 12B staging E2E .. tool/run_supabase_12b_staging_e2e.sh
10. run 12C staging E2E .. tool/run_supabase_12c_staging_e2e.sh
11. run Realtime E2E ..... tool/run_supabase_12c_realtime_staging_e2e.sh
12. benchmark ........... tool/run_benchmark_supabase_12c_staging.sh
13. review thresholds .... §9
14. retention plan ....... tool/run_plan_supabase_12c_journal_retention.sh
15. fix-forward rehearsal  §7
16. GO/NO-GO ............. §10
17. approve client canary  only after GO
```

Step 3 is the only remote-mutating command not driven by this repository's
tooling. It is `db push`, never `db reset`:

```bash
npx supabase link --project-ref "$STAGING_PROJECT_REF"
npx supabase db push --linked          # applies pending migrations only
npx supabase test db --linked          # pgTAP against staging
```

`supabase db reset` against a linked remote project is forbidden by this rollout
and is refused by the shell preflight if it appears in any argument list.

## 6. Backfill

### Why a backfill is needed at all

`20260803000100` starts the journal empty. A device pulling from cursor 0
therefore receives only rows that have been *touched* since the migration; master
data and open documents that predate it stay invisible until someone edits them.
A fresh install would come up with an empty catalogue.

### Why not "touch every row"

`UPDATE ... SET updated_at = updated_at` would let the existing triggers write
the journal themselves, which is simpler. It is also wrong: the metadata trigger
raises `server_version` on every touched row, which moves every `field_version`
with it, which makes the server win every field on the next three-way merge. Any
device holding a pending local edit loses it silently. The rollout does not do
this, and the migration comment says so at the top so nobody reintroduces it.

### What the backfill does instead

For each live row of each syncable table, in a fixed type order, it inserts one
journal entry carrying the row's **existing** `server_version` and
`server_updated_at`, plus baseline `sync_entity_field_versions` rows for the
mergeable fields. It never writes a business column, never raises a version,
never creates a movement, and never changes `updated_at`.

Granularity matches the live feed: masters and document headers are journalled
per aggregate (line tables are covered by their parent), while `stock_movement`
and `stock_balance` are journalled per row.

### Idempotency

`public.sync_change_journal_backfill_marks` has primary key
`(backfill_revision, entity_type, entity_id)`. A second run — same run id, a
different run id, or a concurrent one — loses the insert race and counts the
entity as skipped. This is a constraint, not a `NOT EXISTS` check, precisely
because two operators can run at once. An advisory transaction lock on top makes
that case *visible* rather than merely harmless.

An entity that already has any journal entry is skipped too: a runtime write has
already put it in the feed, and replaying it would resend a change devices have
seen.

### Operation

```bash
# Always dry-run first. Writes nothing at all — not even a mark.
bash tool/run_supabase_12c_backfill_staging.sh --dry-run

# Then execute. One batch per round trip, each committing on its own.
bash tool/run_supabase_12c_backfill_staging.sh --execute

# Resume an interrupted run from the server's own checkpoint.
bash tool/run_supabase_12c_backfill_staging.sh --execute --resume <run-id>

# Narrow the scope, e.g. to redo one type.
bash tool/run_supabase_12c_backfill_staging.sh --execute --entity-types=item,batch
```

Options: `--dry-run`, `--execute`, `--resume <run-id>`, `--run-id <uuid>`,
`--revision <name>`, `--batch-size <1..5000>`, `--entity-types <a,b,c>`,
`--max-batches <n>`.

Per-batch report fields: `run_id`, `entity_type`, `scanned`, `inserted`,
`skipped`, `failed`, `next_checkpoint`, `completed`, `duration_ms`,
`journal_min_seq`, `journal_max_seq`. In a dry run `inserted` means *would
insert*; the report carries `dry_run: true` so it cannot be misread.

Exit code is 0 only when the server reported `completed` with zero failures.

### Failure behaviour

A per-entity failure is caught, counted, and stops the batch. The checkpoint
stays on the last entity that actually succeeded, and the failed entity's mark is
rolled back with it — so a resumed run retries that entity rather than stepping
over it. There is no such thing as a checkpoint past a failure.

### Timing

Run the backfill during a low-traffic window, but note that it takes no
exclusive locks: it only reads business tables and inserts into the journal.
It can be paused at any batch boundary and resumed later.

## 7. Rollback and fix-forward

**A full schema rollback is not the default and is not recommended once any
client has stored a cursor.** Dropping the journal makes every stored cursor
point at a position that no longer exists; those devices receive
`sync_cursor_invalid` and resync from zero. That recovery is correct, but it
happens to every device simultaneously.

Prefer fix-forward. In escalating order:

| Symptom | Action | Effect |
| --- | --- | --- |
| A scope leak is suspected | `revoke execute on function public.pull_sync_changes(bigint,integer,uuid,text[]) from authenticated;` | Pull stops; 12B push keeps working; clients fall back to push-only |
| Realtime load is too high | `alter publication supabase_realtime drop table public.sync_change_journal;` | Invalidation stops; pull still runs on login, resume, reconnect and manual sync |
| Journal write load is too high on one table | `alter table public.<table> disable trigger trg_<table>_change_journal;` | That table stops feeding the journal; clients are not broken, they just stop receiving its changes |
| Backfill is producing wrong entries | Stop the driver; the marks table records exactly what was written under which revision | Journal entries stay for investigation; nothing to undo on the business side |
| Journal is too large | Follow §8 with a conservative boundary | — |
| Client v15 is misbehaving | Halt the canary rollout | Server stays as is; v14 clients are unaffected |

In every case: **keep the journal and the marks table.** They are the evidence.

### When a full migration rollback is justified

Only if all of these hold:

- no client build using the pull path has been released to any device;
- the journal contains only backfill entries and staging fixture traffic;
- an operator has confirmed `sync_devices` holds no device belonging to a real
  user of the environment being rolled back.

Then, and only then, dropping `20260803000200` and `20260803000100` is safe. The
risk being avoided is cursor divergence: a device whose cursor survives a journal
that does not.

### Recovery verification

After any fix-forward or rollback, confirm:

- `tool/run_supabase_12b_staging_e2e.sh` passes — push still works end to end;
- authentication still works and `register_sync_device` still succeeds;
- `select count(*) from public.stock_balances where qty_on_hand < 0` returns 0;
- no duplicate movement id exists for any `ref_doc_id`;
- a v14 (push-only) client still syncs;
- a v15 client against an incompatible server fails **closed** on the revision
  health check rather than proceeding.

The fix-forward rehearsal in step 15 is the revoke-and-restore of the pull grant,
performed on staging and timed. Do not skip it: an untested rollback is a NO-GO
condition in §10.

## 8. Journal retention

Not scheduled, not executed, and not decided by this rollout.

`app_private.prune_sync_change_journal(keep_through)` exists, is private, refuses
to prune at or above the commit horizon, and is called by nothing.

The number that makes a boundary safe is the **lowest cursor across all active
devices** — and that value lives on the devices, not on the server. No query can
produce it. It has to be derived from a product decision about the maximum age a
device may reach while offline, then confirmed against client telemetry.

```bash
bash tool/run_plan_supabase_12c_journal_retention.sh --safety-window-days=30
```

The planner reports `current_max_cursor`, `commit_horizon`,
`proposed_keep_through`, `rows_eligible`, `oldest_change` and
`safety_window_days`, and explicitly reports `current_min_active_cursor` as
unknown rather than guessing it. It deletes nothing and schedules nothing.

Preconditions before any prune is ever approved:

1. The product owner has agreed a maximum offline age for a device.
2. Client telemetry confirms no active device sits below the proposed boundary.
3. The boundary is below the commit horizon (the function enforces this anyway).
4. A verified backup exists.
5. A simultaneous resync-from-zero for any device below the boundary is
   acceptable if the telemetry turns out to be wrong.

A device that falls below the prune boundary receives `sync_cursor_invalid`,
resets its cursor and resyncs from 0. That is safe — apply is idempotent — but
expensive for both the device and the server, and expensive for all of them at
once.

## 9. Performance thresholds

`tool/run_benchmark_supabase_12c_staging.sh` produces a JSON and a Markdown
report under `artifacts/staging/` (gitignored — the reports name the project and
its actors).

Starting thresholds, overridable by environment variable. These are **baseline
observations to detect regression**, not an SLA and not a production projection:

| Measure | Threshold | Variable |
| --- | --- | --- |
| Empty-page pull p95 | 400 ms | `AISH_BENCH_EMPTY_P95_MS` |
| 200-entry page p95 | 2500 ms | `AISH_BENCH_PAGE200_P95_MS` |
| 500-entry page p95 | 5000 ms | `AISH_BENCH_PAGE500_P95_MS` |
| Catch-up from cursor 0 | 15000 ms | `AISH_BENCH_CATCHUP_P95_MS` |

Also reported without a threshold, because there is no defensible number yet:
journal row count and on-disk size, index size, journal rows added per business
write, write latency with the trigger active, commit-horizon settle time after a
burst, and backfill scan throughput.

Bounds the benchmark respects: `AISH_BENCH_SAMPLES` (default 20),
`AISH_BENCH_MAX_FIXTURE_WRITES` (default 600), `AISH_BENCH_CONCURRENCY`
(default 4), `AISH_BENCH_TIMEOUT_MS` (default 30000). It cannot become an
unintended load test.

If staging holds fewer than 500 journal rows the report says so in `notes` and
the figures must not be read as production behaviour. Generate volume with the
bounded fixture writer rather than by pointing the benchmark at real data.

## 10. GO / NO-GO

| Condition | Verdict |
| --- | --- |
| Backup taken **and** restore rehearsed | GO required |
| Any private helper executable by `anon`/`authenticated` | **NO-GO** |
| `admin_*` RPC reachable by a session token | **NO-GO** |
| Backfill incomplete (`missing_baseline_total > 0`) | **NO-GO** |
| Any backfill run reports `failed > 0` | **NO-GO** |
| Duplicate backfill marker found | **NO-GO** |
| Branch isolation fails in the 12C staging E2E | **NO-GO** |
| Realtime delivers a cross-branch frame | **NO-GO** |
| 12B staging E2E fails | **NO-GO** |
| 12C staging E2E fails | **NO-GO** |
| Duplicate movement found | **NO-GO** |
| Negative stock balance found | **NO-GO** |
| Journal or pull latency past the agreed threshold | **NO-GO** |
| Fix-forward not rehearsed on staging | **NO-GO** |
| Working tree not `chore/12c-staging-rollout`, or dirty | **NO-GO** |
| Any script reported a production target | **NO-GO — stop and investigate** |
| Journal RLS not forced, or a non-SELECT policy present | **NO-GO** |
| `sync_change_journal` carries any column beyond the seven bookkeeping ones | **NO-GO** |
| Realtime publication absent | Proceed with a note — the system is correct without it, only slower |
| Staging volume too small for a meaningful benchmark | Proceed with a recorded limitation |

GO permits **the client canary only**. It does not authorise a production
deployment, which is a separate decision with its own runbook.

## 11. What staging cannot tell you

Stated so it is not mistaken for coverage:

- Behaviour at production volume. Every number here comes from staging.
- True concurrent-backfill rejection. The marks primary key makes duplicates
  impossible and the advisory lock serialises runs, but pgTAP runs in one
  transaction and cannot open a second session; the lock is asserted by its
  presence in `pg_locks`, and the duplicate-free property is asserted directly.
- Head-of-line blocking under a genuinely long production transaction. The
  benchmark measures the horizon's reaction to a burst, which is the closest an
  operator tool without a database connection can get.
- Multi-device beyond the fixture set the harnesses create.
- Realtime under sustained production fan-out.
