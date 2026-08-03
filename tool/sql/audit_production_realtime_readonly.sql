-- =====================================================================
-- READ-ONLY production audit of the Realtime configuration for
-- public.sync_change_journal
-- =====================================================================
--
--   branch    : chore/12c-staging-rollout
--   commit    : 8193560
--   change    : GH-2
--   incident  : production E2E canary FAIL 32/33 —
--               realtime/a_scope_change_produces_an_invalidation
--
-- PURPOSE
--   The canary's Realtime check failed while `subscription_established` passed
--   and the pull that followed still supplied the state. This file gathers the
--   production-side configuration needed to confirm or refute each remaining
--   hypothesis, without changing anything.
--
-- SAFETY
--   Every statement is a SELECT against catalogue views. Nothing here alters a
--   publication, a policy, RLS, a grant or a replica identity. Running it
--   changes nothing.
--
-- HOW TO RUN
--   Paste into the Supabase SQL Editor for project mfj*…**tp and run.
--
-- STATUS
--   READ-ONLY REALTIME AUDIT = PENDING until an operator runs this and attaches
--   the output.
--
-- WHAT IS ALREADY KNOWN, AND THEREFORE NOT IN QUESTION
--   Publication membership is already proven twice over and section 1 is a
--   re-confirmation, not an open question:
--     * the preflight at 2026-08-03T15:31:19Z recorded
--       journal.in_realtime_publication = true;
--     * the backup taken at 2026-08-03T15:28:02Z contains, at schema.sql:6158,
--       ALTER PUBLICATION "supabase_realtime"
--         ADD TABLE ONLY "public"."sync_change_journal";
--   Absence of the table from the publication is NOT the cause.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Publication membership
--    Expected: exactly one row.
-- ---------------------------------------------------------------------
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'sync_change_journal';

-- Publication-level settings. `pubinsert` must be true or an INSERT
-- subscription can never fire.
select pubname, pubowner::regrole::text as owner,
       puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
from pg_publication
where pubname in ('supabase_realtime', 'supabase_realtime_messages_publication');

-- ---------------------------------------------------------------------
-- 2. RLS and replica identity
--    Expected from the backup: relrowsecurity = t, relforcerowsecurity = t,
--    relreplident = 'd'. `d` (DEFAULT, i.e. primary key) is sufficient for
--    INSERT events, which is all this subscription asks for.
-- ---------------------------------------------------------------------
select
  c.relrowsecurity,
  c.relforcerowsecurity,
  c.relreplident
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'sync_change_journal';

-- ---------------------------------------------------------------------
-- 3. Policies
--    Expected: exactly one, sync_change_journal_read_scope, SELECT, granted to
--    {authenticated}. Realtime evaluates this same predicate per subscriber, so
--    if it cannot be satisfied, no frame is delivered however healthy the
--    channel looks.
-- ---------------------------------------------------------------------
select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'sync_change_journal'
order by policyname;

-- ---------------------------------------------------------------------
-- 4. Grants
--    Expected:
--      authenticated SELECT   true
--      anon          SELECT   false
--      authenticated INSERT   false
--      anon          INSERT   false
--
--    The anon row matters more than it looks. If the subscriber's JWT never
--    reached the Realtime socket, Realtime evaluates the subscription as anon,
--    and anon having no SELECT is exactly what would make every frame vanish
--    while the transport reported SUBSCRIBED.
-- ---------------------------------------------------------------------
select
  r.rolname                                                                   as role,
  has_table_privilege(r.rolname, 'public.sync_change_journal', 'select')       as can_select,
  has_table_privilege(r.rolname, 'public.sync_change_journal', 'insert')       as can_insert,
  has_table_privilege(r.rolname, 'public.sync_change_journal', 'update')       as can_update,
  has_table_privilege(r.rolname, 'public.sync_change_journal', 'delete')       as can_delete
from pg_roles r
where r.rolname in ('anon', 'authenticated', 'service_role', 'supabase_realtime_admin')
order by r.rolname;

-- RPC and private helper privileges: the pull path must stay reachable by
-- authenticated and closed to anon, and the visibility oracle must stay private.
select
  p.oid::regprocedure::text                                        as function,
  has_function_privilege('authenticated', p.oid, 'execute')        as authenticated_execute,
  has_function_privilege('anon',          p.oid, 'execute')        as anon_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public'      and p.proname in ('pull_sync_changes', 'register_sync_device'))
   or (n.nspname = 'app_private' and p.proname in ('pull_entity_visible',
                                                   'pull_entity_payload',
                                                   'current_user_is_active'))
order by 1;

-- ---------------------------------------------------------------------
-- 5. Publication state and replication plumbing
--
--    This is where the leading hypothesis is decided. Locally, the first
--    postgres_changes subscriber after the Realtime service starts receives no
--    frame at all — the change is lost, not delayed — because the tenant's CDC
--    pipeline is brought up lazily and a logical slot only ever streams WAL
--    written after it exists. Production had never had a Realtime subscriber
--    before the canary: the preflight recorded 0 journal rows and 0 registered
--    devices.
--
--    Expected if the hypothesis holds: a supabase_realtime replication slot
--    that either does not exist, or whose creation postdates the canary's
--    mutation at ~2026-08-03T15:32:5xZ.
-- ---------------------------------------------------------------------
select
  slot_name,
  plugin,
  slot_type,
  active,
  confirmed_flush_lsn,
  wal_status
from pg_replication_slots
order by slot_name;

-- Realtime's own subscription registry. A row here means a subscriber is
-- currently attached; an empty table with a healthy channel is itself a finding.
-- The table is created by the Realtime service's own migrations, so a project
-- that has never run Realtime does not have it — and that absence is an answer
-- in itself, not an error to trip over. A runtime guard is not enough here:
-- Postgres resolves every relation in a statement at parse time, so naming
-- `realtime.subscription` directly would fail before any guard could run. The
-- catalogue is asked instead.
select
  to_regclass('realtime.subscription') is not null       as subscription_table_exists,
  (select c.reltuples::bigint
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'realtime' and c.relname = 'subscription') as subscription_rows_estimate;

-- Only if the row above says the table exists, run this for an exact count:
--   select count(*) as realtime_subscription_rows from realtime.subscription;

-- The journal's shape, for the record: change_seq is the primary key, which is
-- what a DEFAULT replica identity relies on.
select
  a.attname                            as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null
from pg_attribute a
where a.attrelid = 'public.sync_change_journal'::regclass
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

select
  i.indisprimary,
  i.indisunique,
  array_to_string(array_agg(a.attname order by a.attnum), ',') as columns
from pg_index i
join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
where i.indrelid = 'public.sync_change_journal'::regclass
group by i.indisprimary, i.indisunique;

-- Journal triggers: the row has to be written before it can be replicated.
select
  t.tgname                       as trigger_name,
  p.oid::regprocedure::text      as function,
  t.tgenabled                    as enabled
from pg_trigger t
join pg_proc p on p.oid = t.tgfoid
where t.tgrelid = 'public.rooms'::regclass
  and not t.tgisinternal
order by t.tgname;

-- ---------------------------------------------------------------------
-- 6. The application's own rollout verification, for cross-checking
--    Read-only by contract; it reports grants, policies, trigger presence and
--    publication membership as one JSON document.
-- ---------------------------------------------------------------------
-- select public.admin_sync_rollout_verification();
--   ^ service_role only. Left commented out: it is a function call rather than
--     a plain SELECT on a catalogue, and this file's guarantee is that every
--     statement in it is inert. Run it separately if the audit above leaves
--     anything open.
