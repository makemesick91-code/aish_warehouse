#!/usr/bin/env bash
set -euo pipefail

# Fix-forward reference for the production canary.
#
# This script PRINTS commands. It does not run them, it does not connect to
# anything, and it does not read a credential. That is deliberate: a recovery
# action on production is a decision a human makes with a second human watching,
# not something a script decides it is time for. Every command below is meant to
# be read, understood, and pasted by an operator who has decided to run it.
#
#   bash tool/production_fix_forward.sh                    # list symptoms
#   bash tool/production_fix_forward.sh --symptom=scope_leak
#   bash tool/production_fix_forward.sh --stop-conditions
#
# A full schema rollback is not in here as a routine option, and §"rollback" says
# why: once any device has stored a cursor, dropping the journal invalidates all
# of them at once.

SYMPTOM=""
SHOW_STOP=0

for argument in "$@"; do
  case "$argument" in
    --symptom=*) SYMPTOM="${argument#--symptom=}" ;;
    --stop-conditions) SHOW_STOP=1 ;;
    --help|-h) SYMPTOM="" ;;
    *)
      echo "unknown argument: ${argument}" >&2
      exit 2
      ;;
  esac
done

banner() {
  echo ""
  echo "=============================================================="
  echo "  $1"
  echo "=============================================================="
  echo ""
}

note() {
  echo "  $1"
}

command_block() {
  echo ""
  while IFS= read -r line; do
    echo "    ${line}"
  done
}

print_stop_conditions() {
  banner "STOP CONDITIONS — halt the canary, do not proceed carefully"
  cat <<'TEXT'

  Evaluated automatically by tool/run_supabase_production_preflight.sh. Run it
  before the canary and again after every step.

  Authorisation
    - the maintenance window has closed, or has under 30 minutes left
    - the change ticket has been withdrawn or superseded
    - the backup identifier cannot be resolved to a retrievable backup
    - the restore rehearsal was not performed against THIS backup
    - the working tree is dirty, or is not the authorised branch

  Server posture
    - any app_private helper is executable by anon or authenticated
    - any admin_* RPC is reachable with a session token
    - anon can call pull_sync_changes
    - the journal has RLS disabled, RLS not forced, or a non-SELECT policy
    - the journal carries any column beyond the seven bookkeeping ones
    - the journal immutability trigger is absent
    - the backfill marks or runs table is readable by a session
    - max change_seq sits below the commit horizon

  Backfill canary
    - any invariant violation between two batches — stop at that boundary
    - any business row count, updated_at, server_version, movement count or
      balance total changed during a batch
    - duplicate backfill marks is not zero
    - the run ledger checkpoint disagrees with the batch report
    - a batch reported failed > 0
    - a second open run exists under the same revision

  Canary harnesses
    - a Realtime frame crossed a branch boundary
    - a frame carried a business column
    - branch isolation failed in any direction
    - a replayed push was performed instead of recognised
    - duplicate movements greater than zero, in any scan window
    - any negative stock balance
    - the canary namespace could not be retired

  Client
    - a released client fails its revision health check open rather than closed
    - error rate or sync failure rate rises after the canary

TEXT
}

print_symptom() {
  case "$1" in
    scope_leak)
      banner "SYMPTOM: a scope leak is suspected in the pull feed"
      note "Effect: pull stops for every client. 12B push keeps working, so the"
      note "app falls back to push-only. This is the cheapest real rollback."
      command_block <<'TEXT'
revoke execute on function
  public.pull_sync_changes(bigint, integer, uuid, text[])
  from authenticated;
TEXT
      note "To restore, once the leak is understood and fixed:"
      command_block <<'TEXT'
grant execute on function
  public.pull_sync_changes(bigint, integer, uuid, text[])
  to authenticated;
TEXT
      note "Verify either direction with:"
      command_block <<'TEXT'
bash tool/run_verify_supabase_production_migrations.sh
TEXT
      ;;

    realtime_load)
      banner "SYMPTOM: Realtime load is too high"
      note "Effect: invalidation stops. Pull still runs on login, resume,"
      note "reconnect and manual sync, so the system stays correct — only"
      note "slower to notice a change."
      command_block <<'TEXT'
alter publication supabase_realtime drop table public.sync_change_journal;
TEXT
      note "To restore:"
      command_block <<'TEXT'
alter publication supabase_realtime add table public.sync_change_journal;
TEXT
      ;;

    journal_write_load)
      banner "SYMPTOM: journal write load is too high on one table"
      note "Effect: that table stops feeding the journal. Clients are not"
      note "broken; they simply stop receiving that table's changes until the"
      note "trigger is re-enabled and the table is re-backfilled."
      note "Replace <table> with the busiest one, e.g. stock_movements."
      command_block <<'TEXT'
alter table public.<table> disable trigger trg_<table>_change_journal;
TEXT
      note "To restore, re-enable and then backfill that entity type only:"
      command_block <<'TEXT'
alter table public.<table> enable trigger trg_<table>_change_journal;

bash tool/run_supabase_production_backfill_canary.sh \
  --max-batches=10 --entity-types=<entity_type> --execute
TEXT
      ;;

    backfill_wrong)
      banner "SYMPTOM: the backfill is producing entries that look wrong"
      note "Stop the driver. Do NOT delete anything: the marks table records"
      note "exactly what was written, under which revision, by which run."
      note "That is the evidence, and there is nothing to undo on the business"
      note "side because the backfill writes no business column."
      command_block <<'TEXT'
# 1. Stop the driver (Ctrl-C). The last batch has already committed on its own.
# 2. Read the audit record it wrote:
ls -t artifacts/production/production-backfill-*.json | head -1

# 3. Inspect what that run marked, as service_role:
select entity_type, count(*)
  from public.sync_change_journal_backfill_marks
 where run_id = '<run-id>'
 group by entity_type;
TEXT
      note "A wrong entry is a journal row, not a business row. Investigate"
      note "before touching it; the journal is append-only by design."
      ;;

    backfill_stuck)
      banner "SYMPTOM: a backfill run is open and will not resume"
      note "The driver refuses to start a second run under the same revision"
      note "while one is open. Resume it rather than starting another."
      command_block <<'TEXT'
# Find the open run:
select run_id, backfill_revision, entity_types, updated_at, scanned,
       inserted, skipped, failed, completed
  from public.sync_change_journal_backfill_runs
 where completed = false
 order by updated_at desc;

# Resume it:
bash tool/run_supabase_production_backfill_canary.sh \
  --max-batches=4 --execute --resume <run-id>
TEXT
      ;;

    journal_too_large)
      banner "SYMPTOM: the journal is too large"
      note "Retention is NOT decided by this rollout, and no prune is"
      note "scheduled. The safe boundary is the lowest cursor across all active"
      note "devices, which lives on the devices and cannot be queried."
      note "Plan it first; the planner deletes nothing."
      command_block <<'TEXT'
bash tool/run_plan_supabase_12c_journal_retention.sh --safety-window-days=30
TEXT
      note "A prune is only approved once the product owner has agreed a maximum"
      note "offline age, telemetry confirms no active device sits below the"
      note "boundary, and a verified backup exists."
      ;;

    canary_stuck)
      banner "SYMPTOM: a canary namespace could not be retired"
      note "Retire it by hand. Soft retirement only — never delete."
      note "The namespace token is in the harness report."
      command_block <<'TEXT'
ls -t artifacts/production/production-canary-e2e-*.json | head -1

# As service_role, retire what the report lists under rows_created:
update public.<table>
   set deleted_at = now(), updated_at = now()   -- add is_active = false where the column exists
 where id = any('{<id>,<id>}'::uuid[]);

# Ban the canary logins (never delete them; the link row is a hard delete):
-- through the Supabase dashboard: Authentication > Users > ban
-- the canary accounts are the ones on @aish-canary.invalid
TEXT
      ;;

    client_misbehaving)
      banner "SYMPTOM: the canary client build is misbehaving"
      note "Halt the client rollout. The server stays exactly as it is;"
      note "previous-revision clients are unaffected because no public RPC"
      note "signature changed."
      command_block <<'TEXT'
# 1. Halt the canary distribution in the store / MDM console.
# 2. Confirm the server is unchanged:
bash tool/run_verify_supabase_production_migrations.sh
# 3. Confirm push still works for the previous client revision:
bash tool/run_supabase_production_canary_e2e.sh
TEXT
      ;;

    rollback)
      banner "SYMPTOM: a full schema rollback is being considered"
      note "It is not recommended and it is not the default. Dropping the"
      note "journal makes every stored cursor point at a position that no"
      note "longer exists; those devices receive sync_cursor_invalid and"
      note "resync from zero — correct recovery, but for all of them at once."
      note ""
      note "It is only justified when ALL of these hold:"
      note "  - no client build using the pull path has reached any device;"
      note "  - the journal holds only backfill entries and canary traffic;"
      note "  - sync_devices holds no device belonging to a real user."
      note ""
      note "Prefer scope_leak, realtime_load or journal_write_load first."
      note "If the rollback is still the decision, it is a restore from the"
      note "recorded backup identifier, performed by the operator, not a DROP."
      ;;

    *)
      echo "unknown symptom: $1" >&2
      echo "" >&2
      list_symptoms >&2
      exit 2
      ;;
  esac
}

list_symptoms() {
  banner "FIX-FORWARD — production canary"
  cat <<'TEXT'

  Nothing here is executed by this script. Every command is printed to be read
  and run by an operator who has decided to run it.

  In escalating order of cost:

    --symptom=scope_leak          revoke pull; clients fall back to push-only
    --symptom=realtime_load       drop the journal from the publication
    --symptom=journal_write_load  disable one table's journal trigger
    --symptom=backfill_wrong      stop the driver; keep the marks as evidence
    --symptom=backfill_stuck      resume an open run instead of starting another
    --symptom=journal_too_large   plan retention; nothing is pruned by this rollout
    --symptom=canary_stuck        retire a canary namespace by hand, softly
    --symptom=client_misbehaving  halt the client canary; server unchanged
    --symptom=rollback            why a full rollback is the last option

    --stop-conditions             when to halt rather than proceed carefully

  In every case: keep the journal and the marks table. They are the evidence.

TEXT
}

if [[ "$SHOW_STOP" == "1" ]]; then
  print_stop_conditions
fi

if [[ -n "$SYMPTOM" ]]; then
  print_symptom "$SYMPTOM"
elif [[ "$SHOW_STOP" != "1" ]]; then
  list_symptoms
fi

echo ""
