#!/usr/bin/env bash
set -euo pipefail

# Milestone 12C pull-path end-to-end, against staging.
#
# Staging only. Never calls `supabase db reset`, never touches a local stack,
# and reads every credential from the operator environment. See
# `.env.staging.example` and `docs/supabase_12c_staging_rollout.md`.

source "$(dirname "${BASH_SOURCE[0]}")/staging_preflight.sh"

staging_preflight "supabase_12c_staging_e2e" require_service_role

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/supabase_12c_staging_e2e.ts "$@"
