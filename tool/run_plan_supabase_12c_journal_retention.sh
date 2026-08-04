#!/usr/bin/env bash
set -euo pipefail

# Milestone 12C journal retention planner. Proposes a boundary; deletes nothing.
#
# Staging only. Never calls `supabase db reset`, never touches a local stack,
# and reads every credential from the operator environment. See
# `.env.staging.example` and `docs/supabase_12c_staging_rollout.md`.

source "$(dirname "${BASH_SOURCE[0]}")/staging_preflight.sh"

staging_preflight "plan_supabase_12c_journal_retention" require_service_role read_only

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/plan_supabase_12c_journal_retention.ts "$@"
