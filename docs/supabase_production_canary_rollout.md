# Milestone 12C — production canary rollout runbook

Server revision `aish-supabase-003`. This document covers taking revision 003 to
the **production** project as a canary: verifying the migrations without writing
anything, seeding the change journal in small guarded batches with a business
invariant check between every one of them, exercising the sync contract inside a
dedicated canary namespace, taking low-load measurements, and deciding whether
the client canary may proceed.

> **Status.** Local validation has been run in full: analyzer clean, pgTAP
> green, every guard refusal exercised. The Flutter suite has 40 pre-existing,
> date-dependent failures — the same 40 the staging commit recorded, and they
> reproduce on `HEAD` without this branch. §15 names them.
>
> **The migrations have since been applied to the production project, before an
> approved preflight ever ran.** That is an incident, and it is recorded in
> `supabase_12c_production_rollout_incident.md` — cause, containment, backup and
> restore evidence, and live verification. Earlier revisions of this document
> stated that no command here had been run against a remote project; that
> statement was true when written and is no longer true. §15 carries the
> corrected status.
>
> The **canary** steps — backfill, E2E, Realtime, benchmark — remain BLOCKED
> pending production credentials, a change ticket, an approved maintenance
> window and an operator acknowledgement. Backfill is separately **SKIPPED**:
> live production holds zero rows in every table it would touch.

## 1. This is a separate path, not a staging variant

The operator has one remote Supabase project, and it is production. Nothing in
this rollout treats it as staging, and nothing in it weakens the staging guard so
that production can pass through it.

| | Staging path | Production canary path |
| --- | --- | --- |
| Guard | `tool/staging_guard.ts` | `tool/production_guard.ts` |
| Shell preflight | `tool/staging_preflight.sh` | `tool/production_preflight.sh` |
| Environment contract | `.env.staging.example` | `.env.production.example` |
| Confirmation | `AISH_STAGING_CONFIRM` | `AISH_PRODUCTION_CONFIRM` + a second confirmation |
| Target selection | host/ref **allowlists** | one **exact** host, one **exact** ref |
| Default mode | mutating harnesses are normal | read-only or dry-run, always |
| Fixtures | full fixture set, per-run namespace | minimal canary namespace, hard row ceiling |
| Artifacts | `artifacts/staging/` | `artifacts/production/` |
| Runbook | `supabase_12c_staging_rollout.md` | this document |

The two contracts must never be loaded into the same shell. Every production
tool refuses to start if any `AISH_STAGING_*` variable is present, and
`tool/production_guard_test.ts` asserts that the staging token is not accepted as
a production confirmation and that the production token is not accepted as a
staging one.

**The staging tooling is unchanged by this rollout.** Not one line of
`staging_guard.ts`, `staging_preflight.sh` or any `*_staging*` tool is modified.
If a staging project becomes available later, that path still works exactly as
it did.

## 2. Configuration

Operator variables live in the environment, never in the repository. The tracked
contract is `.env.production.example`; it carries names and placeholders only.

```bash
# In a NEW shell with no staging environment loaded.
set -a; . /path/outside/the/repo/production.env; set +a
```

The Flutter side uses `config/supabase.production.example.json`, copied to
`config/supabase.production.json` (gitignored). Only the publishable/anon key
ever belongs in a client build.

### 2.1 The production guard

Eight independent facts, none with a default, all supplied in advance:

| Rule | Refusal code |
| --- | --- |
| `AISH_TARGET_ENV` must be `production` | `production_target_env_invalid` |
| `AISH_PRODUCTION_CONFIRM` must equal `I_UNDERSTAND_THIS_TARGETS_PRODUCTION` | `production_confirmation_missing` |
| `AISH_PRODUCTION_SECOND_CONFIRM` must restate `AISH_PRODUCTION_PROJECT_REF` | `production_second_confirmation_mismatch` |
| Any `AISH_STAGING_*` variable present in the shell | `production_staging_environment_present` |
| URL must be HTTPS | `production_url_not_https` |
| Host must equal `AISH_PRODUCTION_ALLOWED_HOST` exactly — no wildcard, no list | `production_host_mismatch` / `production_allowed_host_not_exact` |
| Ref parsed from the URL must equal `AISH_PRODUCTION_PROJECT_REF` | `production_project_ref_mismatch` |
| `AISH_CHANGE_TICKET` must be present and well formed | `production_change_ticket_malformed` |
| `AISH_MAINTENANCE_WINDOW` must be an ISO interval containing *now*, at most 12h wide | `production_maintenance_window_*` |
| `AISH_BACKUP_IDENTIFIER` must name a retrievable backup | `production_backup_identifier_missing` |
| `AISH_RESTORE_REHEARSAL_CONFIRMED` must be `true` | `production_restore_rehearsal_not_confirmed` |
| `AISH_OPERATOR_ACKNOWLEDGEMENT` must name the operator | `production_operator_acknowledgement_implausible` |
| Working tree must be the branch in `AISH_PRODUCTION_ALLOWED_BRANCH` | `production_branch_refused` |
| Working tree must be clean — for read-only runs too | `production_working_tree_dirty` |
| A write must request a scope the operator granted by name | `production_write_scope_not_granted` |
| Any `AISH_ALLOW_*` / `PRODUCTION_ALLOW_DESTRUCTIVE_OPERATIONS` escape hatch set | `production_escape_hatch_refused` |
| Any loop without an explicit bound | `production_batch_limit_required` |
| Any argument resembling `db reset`, `drop`, `truncate`, `--force`, `burst`, `stress`, `mass-fixture`, `failure-injection` | `production_destructive_command_refused` |

### 2.2 Double confirmation

Two distinct acts, plus a third at the terminal:

1. `AISH_PRODUCTION_CONFIRM=I_UNDERSTAND_THIS_TARGETS_PRODUCTION` — "I know this
   is production."
2. `AISH_PRODUCTION_SECOND_CONFIRM=<the exact project ref>` — "and I know *which*
   production." A copied environment file already carries the token; restating
   the ref is a separate decision.
3. At a TTY, `production_preflight.sh` asks for the project ref again and
   compares what was typed. Without a terminal it falls back to the variable and
   records in the artifact that the non-interactive path was taken.

### 2.3 Write scopes

Every production tool is read-only or dry-run by default. A tool that writes must
name a scope, and `AISH_PRODUCTION_WRITE_SCOPE` must grant that same scope. There
is no `all`.

| Scope | What it permits | What it still cannot do |
| --- | --- | --- |
| `journal_baseline` | `admin_backfill_sync_change_journal` inserts into `sync_change_journal` and `sync_entity_field_versions` | touch any business column, raise any `server_version`, move any `updated_at` |
| `canary_namespace` | create and retire the canary's own branches, rooms, locations, catalogue, accounts and documents | touch a row it did not create, post a stock movement, delete anything |

No script prints a key. `production_guard.ts` registers every secret it reads and
scrubs it from every line — including interpolated PostgREST error bodies —
before it reaches stdout. Project refs are masked in artifacts.

## 3. The backup blocker

**Nothing runs without a backup identifier and a rehearsed restore.** This is not
advisory and there is no bypass flag; it is checked twice, once in the shell
before a credential is read into a process and once in the guard.

```bash
# 1. Take the backup. $PRODUCTION_DB_URL comes from the operator environment and
#    is never written down. Nothing in this repository stores a connection string.
pg_dump --format=custom --no-owner --no-privileges \
  --file="production-$(date -u +%Y%m%dT%H%M%SZ).dump" "$PRODUCTION_DB_URL"

# 2. Prove it is readable.
pg_restore --list production-*.dump > /dev/null && echo "dump readable"
sha256sum production-*.dump | tee production-backup-checksums.txt

# 3. REHEARSE THE RESTORE into a scratch database that is neither production
#    nor anything else that matters.
createdb aish_restore_probe
pg_restore --no-owner --dbname=aish_restore_probe production-*.dump
psql -d aish_restore_probe -c "select count(*) from public.sync_change_journal"
psql -d aish_restore_probe -c "select count(*) from public.stock_movements"
dropdb aish_restore_probe

# 4. Only now:
export AISH_BACKUP_IDENTIFIER="production-20260810T2200Z.dump"
export AISH_BACKUP_SHA256="<from step 2>"
export AISH_RESTORE_REHEARSAL_CONFIRMED=true
```

An unrestored dump is a hope, not a rollback plan. Record the Supabase Storage
bucket listing and object count alongside the dump; storage metadata is not in
the database dump.

## 4. Production preflight

```bash
bash tool/run_supabase_production_preflight.sh
```

Read-only. One authenticated connection, one reporting RPC, one JSON artifact.
It verifies the authorisation chain and evaluates every stop condition in §11
against the live project. Run it **before** the canary and **again after every
step**.

What it records — this is the change record the ticket is closed against:

| Field | Where from |
| --- | --- |
| Exact project ref (masked) and exact host | guard, matched against the URL |
| Current git branch, commit, tree cleanliness | shell preflight |
| Change ticket | `AISH_CHANGE_TICKET` |
| Maintenance window, and minutes remaining | `AISH_MAINTENANCE_WINDOW` |
| Backup identifier, checksum, restore rehearsal | `AISH_BACKUP_*` |
| Operator acknowledgement | `AISH_OPERATOR_ACKNOWLEDGEMENT` |
| Server revision | `admin_sync_rollout_verification().server_revision` |
| Applied migrations | `.migrations` |
| Registered devices | `.devices.total` |
| Journal rows, min/max cursor, commit horizon | `.journal.*` |
| Journal table/index/total bytes | `.journal.*_bytes` |
| Realtime publication state | `.journal.in_realtime_publication` |
| RLS, policies and grants | `.journal.*`, `.privileges.*` |
| Every stop condition, triggered or not | evaluated live |

Exit code 0 is GO. Anything else is NO-GO, and the artifact says which item or
stop condition caused it.

### 4.1 Validate the environment file before sourcing it

Check the file with `bash -n` first, and only then source it:

```bash
bash -n /path/to/production.env || exit 1
( set -a; . /path/to/production.env; set +a
  bash tool/run_supabase_production_preflight.sh )
```

An unquoted `<` or `>` in a value — the shape most placeholders take — is a
redirection, not text. Sourcing such a file aborts part-way through, leaving
some variables set and others not, and the first refusal you see then names
whichever variable happened to come after the broken line rather than the real
fault. This has already cost one debugging cycle; the incident record's §8.1
has the details.

Three fields cannot be derived from anything in this repository and must not be
improvised: `AISH_CHANGE_TICKET` must name a real approved change record,
`AISH_MAINTENANCE_WINDOW` must be the real window and must contain the moment
the command runs, and `AISH_OPERATOR_ACKNOWLEDGEMENT` must name the accountable
operator. The guard checks their shape; only the operator can supply their
truth. `AISH_PRODUCTION_ALLOWED_HOST` takes a bare hostname — no scheme, no
wildcard, no list.

## 5. Runbook order

Each step's gate must pass before the next begins. Re-run step 1 between steps.

```text
 1. preflight ............. tool/run_supabase_production_preflight.sh
 2. backup + rehearsal .... §3, recorded in the environment
 3. verify migrations ..... tool/run_verify_supabase_production_migrations.sh
 4. deploy (if pending) ... npx supabase db push --linked      ← see §5.1
 5. verify migrations ..... tool/run_verify_supabase_production_migrations.sh
 6. backfill DRY RUN ...... tool/run_supabase_production_backfill_canary.sh \
                              --max-batches=2 --entity-types=category
 7. backfill EXECUTE ...... same, plus --execute, one entity type at a time
 8. widen the slice ....... repeat 6–7 per entity type, smallest tables first
 9. preflight ............. stop conditions again
10. Realtime canary ....... tool/run_supabase_production_realtime_canary.sh
11. E2E canary ............ tool/run_supabase_production_canary_e2e.sh
12. measurement .......... tool/run_benchmark_supabase_production_readonly.sh
13. measurement + pull .... same, --with-pull
14. review §11 and §13
15. GO/NO-GO ............. §13
16. client canary ......... only after GO, and only for the canary cohort
```

### 5.1 The one command this repository does not drive

Step 4 is `supabase db push`, run by the operator against the linked project.

```bash
npx supabase link --project-ref "$AISH_PRODUCTION_PROJECT_REF"
npx supabase db push --linked          # applies pending migrations only
```

`supabase db reset` against a linked remote project is **forbidden** by this
rollout and is refused by `production_preflight.sh` if it appears in any argument
list. `npx supabase test db --linked` runs pgTAP *against the target*; it is a
local-only gate here and is not run against production.

## 6. Migration verification

```bash
bash tool/run_verify_supabase_production_migrations.sh
```

Read-only, no fixtures, no actors. It asserts:

- every expected migration is applied, and no unreviewed one is;
- `server_revision` still equals the client contract `aish-supabase-003`;
- `pull_sync_changes` has the exact signature a released client was built
  against, and is still `SECURITY DEFINER`;
- the grant table: `authenticated` may pull, `anon` may not, no `app_private`
  helper is exposed, no `admin_*` RPC is reachable from a session;
- **and then the same refusals over the wire**, with a real anon key. A grant
  table is a description; these are the running server's answers. Every call is
  one the server must refuse, so a pass leaves nothing behind;
- the journal: RLS enabled and forced, exactly one SELECT policy targeting
  `authenticated`, no INSERT/UPDATE/DELETE for a session, the immutability
  trigger present, exactly the seven bookkeeping columns, 26 journal triggers,
  7 field-version triggers, max cursor at or above the commit horizon;
- the backfill bookkeeping tables exist and are invisible to a session.

Feed *behaviour* is not verified here. That is the canary E2E's job, and it does
it inside its own namespace rather than against a real user's data.

## 7. Backfill canary

### 7.1 Why a backfill is needed

`20260803000100` starts the journal empty. A device pulling from cursor 0
receives only rows *touched* since the migration; master data and open documents
that predate it stay invisible until someone edits them. A fresh install would
come up with an empty catalogue.

`UPDATE ... SET updated_at = updated_at` would let the existing triggers write
the journal themselves. It is also wrong: the metadata trigger raises
`server_version` on every touched row, which moves every `field_version` with it,
which makes the server win every field on the next three-way merge — silently
losing any pending local edit. The rollout does not do this.

What the backfill does instead: for each live row, in a fixed type order, it
inserts one journal entry carrying the row's **existing** `server_version` and
`server_updated_at`, plus baseline `sync_entity_field_versions` rows. It writes
no business column, raises no version, creates no movement, changes no
`updated_at`. The invariant verifier in §8 is what proves that on the day.

### 7.2 Operation

```bash
# Always dry-run first. Writes nothing at all — not even a mark.
bash tool/run_supabase_production_backfill_canary.sh \
  --max-batches=2 --entity-types=category

# Then execute, one entity type at a time, smallest first.
bash tool/run_supabase_production_backfill_canary.sh \
  --max-batches=2 --entity-types=category --execute

# Resume from the server's own checkpoint.
bash tool/run_supabase_production_backfill_canary.sh \
  --max-batches=4 --execute --resume <run-id>
```

Mandatory on every invocation:

| Flag | Rule |
| --- | --- |
| `--max-batches=<1..50>` | **always required.** There is no "run until done" mode: how much of the window to spend is decided before the run, not after |
| `--entity-types=<a,b,c>` | **required for a first run.** The first thing to touch production is a named slice, not the whole catalogue. Only omittable when `--resume` supplies the scope the run was started with |
| `--execute` | the only way out of dry run. Also requires `journal_baseline` in `AISH_PRODUCTION_WRITE_SCOPE` |
| `--batch-size` | defaults to 25, capped at 100 (the staging default is 500) |

Recommended type order, smallest and least critical first:

```text
category → batch → item → room → stock_location → branch → user
        → stock_opname → purchase_request → delivery_order → good_receipt
        → distribution → disposal → consumption → goods_return
        → stock_balance → stock_movement
```

### 7.3 Concurrency

Refused twice.

`app_private.backfill_sync_change_journal` takes a transactional advisory lock
(`pg_try_advisory_xact_lock`) and raises `sync_backfill_run_in_progress`
(SQLSTATE 55006) if it cannot get it, so two calls can never interleave. That
lock covers one call, though, and a canary is many calls with invariant checks
between them — so the driver also scans the run ledger before it starts and
refuses if another run is open under the same revision within the staleness
window. The result is that the second operator is told *before* anything starts
rather than halfway through.

Idempotency does not depend on either lock: the marks table's primary key is
`(backfill_revision, entity_type, entity_id)`, so a second run — same id,
different id, or concurrent — loses the insert race and counts the entity as
skipped.

### 7.4 Failure behaviour

A per-entity failure is caught, counted, and stops the batch. The checkpoint
stays on the last entity that actually succeeded and the failed entity's mark is
rolled back with it, so a resumed run retries that entity rather than stepping
over it. There is no such thing as a checkpoint past a failure.

## 8. Invariant checks

Taken **before and after every batch**, and again across the whole run. A single
violation aborts at that batch boundary — the batch has already committed on its
own, so stopping is always clean.

| Invariant | How it is measured | Cost on production |
| --- | --- | --- |
| Business row count per watched table | PostgREST `head` + `count=exact` | server-side count, no rows transferred |
| `updated_at` did not move | `max(server_updated_at)`, one ordered row | one row |
| `server_version` did not move | same row | free |
| Movement count unchanged | `head` count on `stock_movements` | server-side count |
| Balances unchanged | `qty_on_hand.sum()` if PostgREST aggregates are enabled, otherwise a **deterministic bounded sample** hashed by primary key | one number, or one bounded page |
| Negative stock is zero | `head` count with `qty_on_hand < 0` | server-side count |
| Duplicate marks are zero | this run's own marks read back and grouped, plus the global `duplicate_marks` from the coverage report at run start and end | bounded by batch size |
| Checkpoint is correct | run ledger compared against the batch's reported `next_checkpoint` | one row |
| Journal grew by exactly what the batch reported | journal row count and mark count | server-side counts |
| A dry run wrote nothing at all | journal and mark counts must be identical | server-side counts |

Two things to know before running this:

- **The balance probe reports its own method.** If PostgREST aggregates are not
  enabled on the project it falls back to hashing a deterministic prefix of the
  table — the same rows on every snapshot, so a change inside that prefix is
  still caught, but it is a sample and the artifact says how many rows it
  covered. It never claims full coverage it did not have.
- **Concurrent application traffic will trip these checks.** That is the intended
  behaviour, not a bug: if a business row changes during a backfill batch, the
  run stops and an operator looks at why. Run inside a window where application
  traffic is drained, or expect to stop.

## 9. Realtime canary

```bash
bash tool/run_supabase_production_realtime_canary.sh
```

Requires `canary_namespace`. Creates a dedicated namespace — its own two
branches, rooms, locations, catalogue and four throwaway accounts on
`@aish-canary.invalid` (a reserved TLD, so a canary account can never email a
real person) — and asserts over real websocket frames:

- a change in the actor's own scope produces an invalidation;
- the frame carries **no business column** and cannot name the new value;
- the state the client ends up with comes from the pull the frame triggered;
- a change outside the actor's scope produces no frame;
- disconnect, change while offline, reconnect, catch up from the cursor;
- logout stops the subscription;
- a second actor's scope fingerprint differs and never receives the first
  actor's frames.

At most six writes, all of them renames of a canary room, asserted against a
budget in code. **No burst, no failure injection, no load.** Those stay local and
on staging.

Cleanup is retirement: `deleted_at` and `is_active = false`, exactly how the
product retires master data. The canary's `sync_devices`, `sync_operations`,
`sync_conflicts` and journal entries are **left in place** as evidence, and the
artifact lists them. The throwaway logins are banned and their passwords rotated
rather than deleted, because deleting an auth user cascades `user_auth_links`.

## 10. E2E canary

```bash
bash tool/run_supabase_production_canary_e2e.sh
```

Requires `canary_namespace`. Seven things and nothing else:

| # | Check |
| --- | --- |
| 1 | a 12B push is accepted, the server assigns the document number, and an identical replay is **recognised**, not performed again |
| 2 | the 12C pull is deterministic: monotonic cursor, the same page from the same cursor, page size 7 and page size 200 see the same sequence, a cursor at the head returns an empty page, a cursor beyond the server is refused |
| 3 | branch isolation, in both directions, between two canary branches; scope fingerprints differ; another actor's device is refused; a client cannot write the journal |
| 4 | a Realtime frame invalidates, and the pull supplies the state — one event, no burst |
| 5 | a disconnected device catches up from its cursor to the server's current state |
| 6 | duplicate movements: zero |
| 7 | negative stock balances: zero |

It pushes exactly one document — a purchase request, chosen because submitting
one posts **no stock movement**. The canary therefore never writes to the ledger,
which is what lets checks 6 and 7 be about production's real health rather than
about the canary's own leftovers. The harness also asserts that the movement
count and balance total are identical before and after itself.

The duplicate-movement scan is bounded: it reads the most recent
`AISH_PRODUCTION_MOVEMENT_SCAN` movements (default 1000) and groups them by
document, item, batch, locations, quantity and type, excluding reversals — a
duplicate has a different primary key, so it can only be found by shape. The
artifact records how many rows were covered and whether that was the whole
ledger. It is a canary-sized window, not a full ledger audit.

## 11. Stop conditions

Evaluated automatically by `run_supabase_production_preflight.sh`, and printable
at any time:

```bash
bash tool/production_fix_forward.sh --stop-conditions
```

Halt — do not proceed carefully — on any of:

**Authorisation.** The window has closed or has under 30 minutes left; the ticket
was withdrawn; the backup identifier cannot be resolved; the rehearsal was not
against *this* backup; the tree is dirty or is not the authorised branch.

**Server posture.** Any `app_private` helper executable by `anon`/`authenticated`;
any `admin_*` RPC reachable with a session token; `anon` can pull; journal RLS not
forced or a non-SELECT policy present; the journal carries any column beyond the
seven; the immutability trigger absent; the marks or runs table readable by a
session; max cursor below the commit horizon.

**Backfill.** Any invariant violation between two batches; any business row count,
`updated_at`, `server_version`, movement count or balance total changed during a
batch; duplicate marks non-zero; the ledger checkpoint disagreeing with the batch
report; `failed > 0`; a second open run under the same revision.

**Canary.** A frame crossing a branch boundary; a frame carrying a business
column; isolation failing in either direction; a replayed push being performed
instead of recognised; duplicate movements above zero; any negative balance; the
namespace failing to retire.

**Client.** A released client failing its revision health check *open* rather than
closed; sync error rate rising after the canary.

## 12. Fix-forward

```bash
bash tool/production_fix_forward.sh                        # list symptoms
bash tool/production_fix_forward.sh --symptom=scope_leak
```

The script **prints** commands and never runs them: a recovery action on
production is a decision a human makes with a second human watching. In
escalating order of cost:

| Symptom | Action | Effect |
| --- | --- | --- |
| A scope leak is suspected | `revoke execute on function public.pull_sync_changes(bigint,integer,uuid,text[]) from authenticated;` | Pull stops; 12B push keeps working; clients fall back to push-only |
| Realtime load is too high | `alter publication supabase_realtime drop table public.sync_change_journal;` | Invalidation stops; pull still runs on login, resume, reconnect and manual sync |
| Journal write load is too high on one table | `alter table public.<table> disable trigger trg_<table>_change_journal;` | That table stops feeding the journal; clients are not broken, they just stop receiving its changes |
| The backfill is producing wrong entries | Stop the driver; keep the marks table | The marks record exactly what was written under which revision by which run. Nothing to undo on the business side |
| A run is open and will not resume | `--resume <run-id>` rather than a second run | The driver refuses a second run by design |
| The journal is too large | `tool/run_plan_supabase_12c_journal_retention.sh` | Plans only. Nothing is pruned by this rollout |
| A canary namespace could not be retired | Retire by hand, softly | Never delete; the ids are in the artifact |
| The client canary misbehaves | Halt the client rollout | Server unchanged; no public RPC signature changed, so previous-revision clients are unaffected |

In every case: **keep the journal and the marks table.** They are the evidence.

A full schema rollback is not the default. Dropping the journal makes every
stored cursor point at a position that no longer exists; those devices receive
`sync_cursor_invalid` and resync from zero — correct recovery, but for all of
them at once. It is only justified when no client using the pull path has reached
any device, the journal holds only backfill and canary entries, and
`sync_devices` holds no real user's device. Otherwise it is a restore from the
recorded backup, performed by the operator.

### Recovery verification

After any fix-forward:

- `bash tool/run_verify_supabase_production_migrations.sh` passes;
- `bash tool/run_supabase_production_canary_e2e.sh` passes — push still works end
  to end;
- negative stock balances: zero;
- duplicate movements in the scan window: zero;
- a previous-revision (push-only) client still syncs;
- a 12C client against an incompatible server fails **closed** on the revision
  health check rather than proceeding.

## 13. Performance, low-load

```bash
bash tool/run_benchmark_supabase_production_readonly.sh              # metrics only
bash tool/run_benchmark_supabase_production_readonly.sh --with-pull  # + latency
```

Default mode is genuinely read-only: one RPC call, no session, no writes. It
reports journal rows, table bytes, index bytes, total bytes, field-version rows,
min/max cursor, commit horizon and registered devices.

`--with-pull` adds empty / 1 / 50 / 200 page latency as p50/p95/max. Measuring a
pull needs an authenticated session with a registered device, which is a write,
so that mode requires `canary_namespace` and retires the namespace afterwards.

Samples are **sequential** with a pause between them:

| Bound | Default | Variable |
| --- | --- | --- |
| Samples per page size | 5 (max 10) | `AISH_PRODUCTION_BENCH_SAMPLES` |
| Concurrency | 1, not configurable | — |
| Pause between samples | 250 ms | `AISH_PRODUCTION_BENCH_PAUSE_MS` |
| Per-call timeout | 15000 ms | `AISH_PRODUCTION_BENCH_TIMEOUT_MS` |

Starting thresholds — regression detectors, not an SLA:

| Measure | Threshold | Variable |
| --- | --- | --- |
| Empty-page pull p95 | 600 ms | `AISH_PRODUCTION_BENCH_EMPTY_P95_MS` |
| 50-entry page p95 | 2000 ms | `AISH_PRODUCTION_BENCH_PAGE50_P95_MS` |
| 200-entry page p95 | 4000 ms | `AISH_PRODUCTION_BENCH_PAGE200_P95_MS` |

Deliberately **not** measured on production, and not going to be: write latency
under the journal trigger, the 50-event burst and commit-horizon settle probe,
concurrent workers, catch-up-from-zero over the whole feed, and backfill
throughput. Those are load generators. They stay local and on staging, where the
staging benchmark already produces them.

## 14. GO / NO-GO

| Condition | Verdict |
| --- | --- |
| Backup recorded **and** restore rehearsed against that backup | GO required |
| Inside an approved maintenance window with time to spare | GO required |
| Preflight exits 0 with no stop condition triggered | GO required |
| Migration verification passes | GO required |
| Backfill dry run clean, then executed slice by slice with zero invariant violations | GO required |
| Realtime canary passes, including cross-branch silence | GO required |
| E2E canary passes all seven groups | GO required |
| Duplicate movements > 0 | **NO-GO** |
| Negative stock balance found | **NO-GO** |
| Any invariant violation during a backfill batch | **NO-GO — stop and investigate** |
| Any private helper executable by `anon`/`authenticated` | **NO-GO** |
| `admin_*` RPC reachable by a session token | **NO-GO** |
| A Realtime frame crossed a branch boundary | **NO-GO** |
| A replayed push was performed rather than recognised | **NO-GO** |
| Any script reported a host or ref other than the declared one | **NO-GO — stop and investigate** |
| Working tree dirty, or not the authorised branch | **NO-GO** |
| Latency past the agreed threshold | **NO-GO** |
| Canary namespace could not be retired | **NO-GO** until retired by hand |
| Realtime publication absent | Proceed with a note — the system is correct without it, only slower |
| PostgREST aggregates unavailable, balance probe sampled | Proceed with a recorded limitation |

GO permits **the client canary cohort only**. It does not authorise a general
release.

## 15. Current status

| Gate | Status |
| --- | --- |
| `flutter analyze` | PASS — no issues |
| `flutter test` (full suite) | 4099 pass, **40 fail** — pre-existing, see below |
| `deno check tool/*.ts` | PASS — all 23 tools, staging and production |
| `deno test --allow-env tool/production_guard_test.ts` | PASS — 21 refusal cases |
| `supabase test db` (pgTAP, local stack, after `db reset`) | PASS — 289 tests |
| `bash -n` on every new shell script | PASS |
| Guard refusals exercised through the runners | PASS — missing env, staging env present, restore not rehearsed, wrong branch, dirty tree, missing write scope |
| `bash tool/production_preflight.sh` refuses direct execution | PASS — exit 64, since `a98fd5d` |
| `bash tool/production_preflight_shell_test.sh` | PASS |

### Remote status — corrected

An earlier revision of this table recorded "every remote production command
BLOCKED — never executed". That is no longer accurate. The migrations were
applied to production before an approved preflight ran; the full record is in
`supabase_12c_production_rollout_incident.md`.

| Remote step | Status |
| --- | --- |
| Migration deploy (11 migrations) | **APPLIED — ungated**, see the incident record |
| Post-migration backup + checksums | PASS — `20260803T095905Z-post-migration` |
| Restore rehearsal, isolated local stack | PASS — 2026-08-03 10:34:53 UTC |
| Live row-count verification | PASS — all fifteen relations 0, 2026-08-03 10:42 UTC |
| Live privilege verification | PASS — `authenticated` may pull, `anon` may not, no private helper reachable |
| Journal backfill | **SKIPPED** — zero rows to baseline |
| Pre-canary backup + checksums | PASS — `20260803T133929Z-pre-canary`, re-verified 2026-08-03 |
| Pre-canary restore rehearsal, isolated local stack | PASS — 2026-08-03 13:45:12 UTC |
| Operator environment contract | **BLOCKED** — file is valid and placeholder-free, five required variables missing; incident record §8.1 |
| Approved production preflight run | **BLOCKED — not run** — no ticket, window, acknowledgement or Supabase keys |
| Live empty-state recheck before canary | **NOT RUN** — requires the guarded read path, which the preflight gates |
| Production canary E2E | **BLOCKED** |
| Realtime canary | **BLOCKED** |
| Low-load benchmark | **NOT RUN** |
| GO / NO-GO | **HOLD** |

The pre-canary backup is a logical dump (`roles.sql`, `schema.sql`, `data.sql`
plus `SHA256SUMS`), not a binary or storage-object backup. It restores the
database; it does not restore Storage objects.

### The `flutter test` failures are pre-existing and unrelated

All 40 are in three wall-clock-dependent seed fixtures and share one cause:

```text
16  test/db/distribution_seed_test.dart
15  test/db/good_receipt_seed_test.dart
 9  test/db/goods_return_seed_test.dart

IneligibleStockOpnameFailure: Stok opname TMP-SO-… tercatat pada minggu yang
belum berjalan. Periksa pengaturan waktu perangkat.
```

The seed builds a stock opname for an ISO week that
`PurchaseRequestSuggestionBuilder._requireEligible` considers not yet started, so
the failure depends on the date the suite is run, not on any code in this branch.
Verified by stashing every change on this branch and running the same file
against a clean `HEAD` (`cfcfb47`): identical failures, identical message. The
count also matches the baseline the staging commit recorded — 4099 pass, 40 fail.

This branch adds no Dart. It touches `tool/*`, `docs/*`, `.gitignore` and two
example config files only. Fixing the seed's week arithmetic is a domain change
and does not belong in a rollout-tooling PR; it is flagged here rather than
quietly absorbed into a "PASS".

The remote steps are blocked on four things, none of which this repository can
supply:

1. **Credentials** — `SUPABASE_URL`, anon key and service-role key for the
   production project.
2. **A backup** — taken, checksummed, and with a restore rehearsed into a scratch
   database. `AISH_BACKUP_IDENTIFIER` and `AISH_RESTORE_REHEARSAL_CONFIRMED`.
3. **A maintenance window** — an approved ISO interval, at most 12 hours, with
   application traffic drained. `AISH_MAINTENANCE_WINDOW`.
4. **A change ticket and an operator acknowledgement** — `AISH_CHANGE_TICKET`,
   `AISH_OPERATOR_ACKNOWLEDGEMENT`.

Until all four exist, every production tool in this branch refuses to start, by
design, and the refusals themselves are tested locally.

Two corrections to what that used to imply:

1. The **migration deploy** did reach production, and it reached it outside
   these tools — through `supabase db push`, with a preflight that silently did
   nothing. No canary tool in this branch has been run against a remote project.
2. A backup and a rehearsed restore now exist, so blocker (2) is satisfied. It
   is satisfied by a **post-migration** backup, which is not a pre-deployment
   restore point; any future production operation needs its own backup taken
   beforehand.

## 16. What a production canary cannot tell you

Stated so it is not mistaken for coverage:

- **Behaviour at full production concurrency.** Everything here is deliberately
  low-load and single-threaded. A canary that could answer this question would be
  a load test, which is not something to point at production.
- **The full ledger's duplicate-movement state.** The scan is a bounded window
  over the most recent movements, and the artifact says how much it covered.
- **Full-table balance integrity when PostgREST aggregates are unavailable.** The
  fallback is a deterministic bounded sample, and it is labelled as one.
- **Head-of-line blocking under a genuinely long production transaction.** No
  tool here opens one, and none should.
- **Realtime under sustained production fan-out.** The canary asserts correctness
  of a small number of frames, not throughput.
- **Multi-device behaviour beyond the canary's own four actors.**
- **Whether the client canary cohort's real usage matches the canary's.** That is
  what the cohort is for; watch it.
