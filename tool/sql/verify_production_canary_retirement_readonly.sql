-- =====================================================================
-- READ-ONLY production verification of the 12C canary namespace retirement
-- =====================================================================
--
--   branch      : chore/12c-staging-rollout
--   commit      : 8193560
--   change      : GH-2
--   namespace   : aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96
--   report      : artifacts/production/production-canary-e2e-2026-08-03T15-33-12-670Z.json
--                 (retirement_ok = true, rows_retired = 19/19,
--                  auth_users_banned = 4/4, rows_missing = 0)
--
-- PURPOSE
--   Confirm, against production itself, that the retirement the canary report
--   claims is actually reflected in the database. The report is the canary's
--   own account of what it did; this file is the independent check.
--
-- SAFETY
--   Every statement below is a SELECT. There is no INSERT, UPDATE, DELETE,
--   TRUNCATE, ALTER, DROP, GRANT, REVOKE, CREATE or COMMENT anywhere in this
--   file, and no function call that mutates. It performs no cleanup: rows that
--   the canary deliberately left in place stay in place. Running it changes
--   nothing.
--
-- HOW TO RUN
--   Paste into the Supabase SQL Editor for project mfj*…**tp and run. Do not
--   pipe it through a shell script that also holds write credentials, and do
--   not run it inside the canary runners.
--
-- STATUS
--   REMOTE RETIREMENT VERIFICATION = PENDING until an operator runs this and
--   attaches the output. Nothing may be recorded as PASS before then.
--
-- KNOWN EVIDENCE GAP — read this before interpreting section 1
--   The canary report records COUNTS (19 created, 19 retired, 0 missing) but
--   NOT the exact row ids it created. Verification by exact id, which would be
--   the strongest form, is therefore impossible from the artefact alone. These
--   queries fall back to the namespace token, which every canary row carries in
--   its name or reaches through its canary branch. That is sound for a SELECT —
--   the prohibition on matching cleanup by name exists because a pattern DELETE
--   can over-match, and nothing here writes — but it is weaker evidence than an
--   id list would be, and a row created outside this namespace could not be
--   distinguished. Recording the created ids in the report is tracked as a
--   follow-up; see docs/supabase_12c_production_rollout_incident.md.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Per-table retirement state
--
--    Expected after a successful retirement:
--      * every table listed here has deleted_at IS NOT NULL on every canary row
--      * branches, rooms, items and users additionally have is_active = false
--      * active_ids = 0 everywhere
--      * the totals across all tables sum to 19
-- ---------------------------------------------------------------------
with ns as (
  select 'aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96'::text as token
),
canary_branches as (
  select b.id from public.branches b, ns where b.name like 'CANARY ' || ns.token || '%'
),
rows_found as (
  -- Tables that carry the namespace in their own name.
  select 'branches'  as table_name, b.id, b.deleted_at, b.is_active
    from public.branches b, ns where b.name like 'CANARY ' || ns.token || '%'
  union all
  select 'rooms', r.id, r.deleted_at, r.is_active
    from public.rooms r, ns where r.name like 'CANARY ' || ns.token || '%'
  union all
  select 'stock_locations', s.id, s.deleted_at, null::boolean
    from public.stock_locations s, ns where s.name like 'CANARY ' || ns.token || '%'
  union all
  select 'item_categories', c.id, c.deleted_at, null::boolean
    from public.item_categories c, ns where c.name like 'CANARY ' || ns.token || '%'
  union all
  select 'items', i.id, i.deleted_at, i.is_active
    from public.items i, ns where i.name like 'CANARY ' || ns.token || '%'
  -- Users carry the namespace in full_name; the remaining tables are reached through the canary branch.
  union all
  select 'users', u.id, u.deleted_at, u.is_active
    from public.users u, ns where u.full_name like 'CANARY ' || ns.token || '%'
  union all
  select 'stock_opnames', o.id, o.deleted_at, null::boolean
    from public.stock_opnames o where o.branch_id in (select id from canary_branches)
  union all
  select 'purchase_requests', p.id, p.deleted_at, null::boolean
    from public.purchase_requests p where p.branch_id in (select id from canary_branches)
  union all
  select 'purchase_request_lines', l.id, l.deleted_at, null::boolean
    from public.purchase_request_lines l
   where l.pr_id in (select p.id from public.purchase_requests p
                      where p.branch_id in (select id from canary_branches))
  union all
  select 'purchase_request_opnames', k.id, k.deleted_at, null::boolean
    from public.purchase_request_opnames k
   where k.pr_id in (select p.id from public.purchase_requests p
                      where p.branch_id in (select id from canary_branches))
)
select
  table_name,
  count(*)                                                as found_ids,
  count(*) filter (where deleted_at is null)              as active_ids,
  count(*) filter (where deleted_at is not null)          as retired_ids,
  count(*) filter (where is_active is true)               as still_flagged_active,
  count(*) filter (where is_active is false)              as flagged_inactive
from rows_found
group by table_name
order by table_name;

-- Expected: 19 found, 19 retired, 0 active.
with ns as (
  select 'aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96'::text as token
),
canary_branches as (
  select b.id from public.branches b, ns where b.name like 'CANARY ' || ns.token || '%'
),
rows_found as (
  select b.deleted_at from public.branches b, ns where b.name like 'CANARY ' || ns.token || '%'
  union all select r.deleted_at from public.rooms r, ns where r.name like 'CANARY ' || ns.token || '%'
  union all select s.deleted_at from public.stock_locations s, ns where s.name like 'CANARY ' || ns.token || '%'
  union all select c.deleted_at from public.item_categories c, ns where c.name like 'CANARY ' || ns.token || '%'
  union all select i.deleted_at from public.items i, ns where i.name like 'CANARY ' || ns.token || '%'
  union all select u.deleted_at from public.users u, ns where u.full_name like 'CANARY ' || ns.token || '%'
  union all select o.deleted_at from public.stock_opnames o where o.branch_id in (select id from canary_branches)
  union all select p.deleted_at from public.purchase_requests p where p.branch_id in (select id from canary_branches)
  union all select l.deleted_at from public.purchase_request_lines l
    where l.pr_id in (select p.id from public.purchase_requests p where p.branch_id in (select id from canary_branches))
  union all select k.deleted_at from public.purchase_request_opnames k
    where k.pr_id in (select p.id from public.purchase_requests p where p.branch_id in (select id from canary_branches))
)
select
  19                                              as report_claims_created,
  19                                              as report_claims_retired,
  count(*)                                        as found_total,
  count(*) filter (where deleted_at is not null)  as retired_total,
  count(*) filter (where deleted_at is null)      as active_total,
  19 - count(*)                                   as unaccounted_for
from rows_found;

-- ---------------------------------------------------------------------
-- 2. Auth identities — read-only, masked, no token or session field
--
--    Expected: exactly 4 canary identities, all with banned_until in the
--    future. They are DISABLED, not deleted; leaving them is the policy.
-- ---------------------------------------------------------------------
select
  left(u.id::text, 8) || '…'                                as auth_user_id_masked,
  left(split_part(u.email, '@', 1), 3) || '…@'
    || split_part(u.email, '@', 2)                          as email_masked,
  (u.banned_until is not null and u.banned_until > now())   as is_currently_banned,
  u.banned_until,
  u.banned_until - now() as remaining_ban,
  u.created_at
from auth.users u
where u.email like '%aish-12c-canary-e2e-2026-08-03T15-32-38-154Z%'
   or u.id in (
     select l.auth_user_id from public.user_auth_links l
     join public.users du on du.id = l.user_id
     where du.full_name like 'CANARY aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96%'
   )
order by u.created_at;

-- Expected: identities = 4, banned = 4, unbanned = 0.
select
  count(*)                                                       as canary_identities,
  count(*) filter (where banned_until is not null
                     and banned_until > now())                   as banned,
  count(*) filter (where banned_until is null
                     or banned_until <= now())                   as not_banned
from auth.users u
where u.id in (
  select l.auth_user_id from public.user_auth_links l
  join public.users du on du.id = l.user_id
  where du.full_name like 'CANARY aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96%'
);

-- ---------------------------------------------------------------------
-- 3. Left in place by policy — this is expected, NOT a cleanup failure
--
--    sync_devices, sync_operations, sync_conflicts, sync_change_journal,
--    sync_entity_field_versions and user_auth_links are kept deliberately:
--    the journal is append-only, the others are the canary's own audit trail,
--    and user_auth_links has no soft-delete contract so the Auth identity is
--    banned instead of the link being destroyed.
-- ---------------------------------------------------------------------
select 'sync_devices' as resource, count(*) as rows_left_in_place
  from public.sync_devices d
 where d.display_label like 'CANARY aish-12c-canary-e2e-2026-08-03T15-32-38-154Z%'
union all
select 'user_auth_links', count(*)
  from public.user_auth_links l
 where l.user_id in (
   select du.id from public.users du
   where du.full_name like 'CANARY aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96%'
 )
union all
select 'sync_operations', count(*)
  from public.sync_operations o
 where o.actor_user_id in (
   select du.id from public.users du
   where du.full_name like 'CANARY aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96%'
 );

-- ---------------------------------------------------------------------
-- 4. Global invariants the canary asserted
--
--    Expected: every count 0, and the journal figures matching the report.
-- ---------------------------------------------------------------------
select
  (select count(*) from public.stock_movements)                       as stock_movements_total,
  (select count(*) from public.stock_balances where qty_on_hand < 0)  as negative_balances,
  -- The same grouping key the canary's own ledger scan uses: reversals and
  -- rows with no source document are excluded, exactly as `scanLedger` does,
  -- so this number is comparable with the one in the report rather than being
  -- a differently-defined second opinion.
  (select count(*) from (
     select ref_doc_type, ref_doc_id, item_id, batch_id,
            from_location_id, to_location_id, qty, movement_type
       from public.stock_movements
      where movement_type <> 'reversal'
        and reversal_of_movement_id is null
        and ref_doc_id is not null
      group by 1,2,3,4,5,6,7,8
     having count(*) > 1
   ) dup)                                                             as duplicate_movement_groups,
  (select count(*) from public.sync_change_journal)                   as journal_rows,
  (select coalesce(max(change_seq), 0) from public.sync_change_journal) as journal_max_cursor;

-- ---------------------------------------------------------------------
-- 5. No canary row is still active anywhere
--
--    Expected: 0. This is the single number that decides whether the namespace
--    is retired in production.
-- ---------------------------------------------------------------------
with ns as (
  select 'aish-12c-canary-e2e-2026-08-03T15-32-38-154Z-cafc2d3d-5a11a3cc96'::text as token
),
canary_branches as (
  select b.id from public.branches b, ns where b.name like 'CANARY ' || ns.token || '%'
)
select count(*) as active_canary_rows_remaining from (
  select 1 from public.branches b, ns
   where b.name like 'CANARY ' || ns.token || '%' and b.deleted_at is null
  union all select 1 from public.rooms r, ns
   where r.name like 'CANARY ' || ns.token || '%' and r.deleted_at is null
  union all select 1 from public.stock_locations s, ns
   where s.name like 'CANARY ' || ns.token || '%' and s.deleted_at is null
  union all select 1 from public.item_categories c, ns
   where c.name like 'CANARY ' || ns.token || '%' and c.deleted_at is null
  union all select 1 from public.items i, ns
   where i.name like 'CANARY ' || ns.token || '%' and i.deleted_at is null
  union all select 1 from public.users u, ns
   where u.full_name like 'CANARY ' || ns.token || '%'
     and u.deleted_at is null
  union all select 1 from public.stock_opnames o
   where o.branch_id in (select id from canary_branches) and o.deleted_at is null
  union all select 1 from public.purchase_requests p
   where p.branch_id in (select id from canary_branches) and p.deleted_at is null

  union all select 1 from public.purchase_request_lines l
   where l.pr_id in (
     select p.id
     from public.purchase_requests p
     where p.branch_id in (select id from canary_branches)
   )
   and l.deleted_at is null

  union all select 1 from public.purchase_request_opnames k
   where k.pr_id in (
     select p.id
     from public.purchase_requests p
     where p.branch_id in (select id from canary_branches)
   )
   and k.deleted_at is null
) still_active;
