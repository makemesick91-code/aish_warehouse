#!/usr/bin/env bash
set -euo pipefail

# Milestone 12C change-journal baseline backfill, against staging.
#
# Unlike the local runners this deliberately does NOT call `supabase status` and
# never calls `supabase db reset`: there is no local stack involved and a reset
# against a remote project is not a thing this repository will help anyone do.
# Credentials come from the operator environment only — see `.env.staging.example`.
#
#   set -a; . /path/outside/the/repo/staging.env; set +a
#   bash tool/run_supabase_12c_backfill_staging.sh --dry-run
#   bash tool/run_supabase_12c_backfill_staging.sh --execute

source "$(dirname "${BASH_SOURCE[0]}")/staging_preflight.sh"

staging_preflight "supabase_12c_backfill_staging" require_service_role

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/supabase_12c_backfill_staging.ts "$@"
